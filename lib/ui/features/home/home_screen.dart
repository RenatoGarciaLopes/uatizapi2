import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zapizapi/services/attachment_service.dart';
import 'package:zapizapi/services/avatar_service.dart';
import 'package:zapizapi/ui/widgets/image_viewer.dart';
import 'package:zapizapi/repositories/profile_repository_implementation.dart';
import 'package:zapizapi/repositories/room_repository_implementation.dart';
import 'package:zapizapi/services/profile_service.dart';
import 'package:zapizapi/services/room_service.dart';
import 'package:zapizapi/ui/features/home/widgets/chat_skeleton.dart';
import 'package:zapizapi/ui/features/home/widgets/open_conversations_sidebar.dart';
import 'package:zapizapi/ui/theme/theme_controller.dart';
import 'package:zapizapi/ui/widgets/custom_input.dart';
import 'package:zapizapi/utils/routes_enum.dart';

// Resultado interno do modal de sugestão de app (web mobile)
enum _AppSuggestionResult { stayOnWeb, goToApp }

// TODO: Implementar controle de sessão
// TODO: Melhorar Arquitatura com viewmodels e services

/// Tela inicial após o login bem-sucedido
class HomeScreen extends StatefulWidget {
  /// Construtor da classe [HomeScreen]
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  String? _selectedRoomId;
  SidebarRoomData? _selectedRoomData;
  Map<String, dynamic>? _replyTargetMessage;
  Map<String, dynamic>? _editingMessage;
  RealtimeChannel? _roomChannel;
  RealtimeChannel? _globalPresenceChannel;
  bool _isPeerOnline = false;
  bool _isPeerTyping = false;
  Timer? _typingResetTimer;
  final Set<String> _onlineUserIds = <String>{};
  String? _directPeerUserId;
  late final AnimationController _introController;
  late final Animation<Offset> _slideIn;
  late final Animation<double> _fadeIn;
  bool _hasHandledInvite = false;
  bool _hasShownAppSuggestion = false;
  int _sidebarReloadKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _slideIn =
        Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _introController,
            curve: Curves.easeOutCubic,
          ),
        );
    _fadeIn = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _introController.forward();
    _subscribeGlobalPresence();
    _checkInviteFromUrl();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingResetTimer?.cancel();
    _roomChannel?.unsubscribe();
    _globalPresenceChannel?.unsubscribe();
    _introController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App voltou para o primeiro plano: volta a marcar presença global
      _subscribeGlobalPresence();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // App foi para segundo plano / ficou inativo: remove presença global
      _globalPresenceChannel?.unsubscribe();
      _globalPresenceChannel = null;
      setState(_onlineUserIds.clear);
    }
  }

  void _checkInviteFromUrl() {
    if (_hasHandledInvite) {
      return;
    }

    final uri = Uri.base;
    String? roomId = uri.queryParameters['room'];

    // Suporte também para o caso em que os parâmetros vêm na âncora (#/invite?room=...)
    if ((roomId == null || roomId.isEmpty) && uri.fragment.isNotEmpty) {
      try {
        final synthetic = Uri.parse(
          'https://fragment${uri.fragment.startsWith('/') ? '' : '/'}${uri.fragment}',
        );
        roomId = synthetic.queryParameters['room'];
      } catch (_) {
        // ignora erros de parse
      }
    }

    // Se não houver convite explícito, ainda assim podemos sugerir o app no mobile web
    if (roomId == null || roomId.isEmpty) {
      _maybeShowAppSuggestionWithoutInvite();
      return;
    }

    _hasHandledInvite = true;

    // Se houver link de convite (room), não mostramos o modal de sugestão.
    // Deixamos o usuário seguir o fluxo normal de convite no site.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showInviteDialog(roomId!);
    });
  }

  bool _isMobileLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Heurística simples: telas estreitas são tratadas como "mobile"
    return size.width < 700;
  }

  void _maybeShowAppSuggestionWithoutInvite() {
    if (!kIsWeb || _hasShownAppSuggestion) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isMobileLayout(context)) return;
      _showAppSuggestionDialog();
    });
  }

  Future<void> _showAppSuggestionDialog({String? roomId}) async {
    if (_hasShownAppSuggestion) return;
    _hasShownAppSuggestion = true;

    final hasInvite = roomId != null && roomId.isNotEmpty;

    final result = await showDialog<_AppSuggestionResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(hasInvite ? 'Abra no app' : 'Melhor no app'),
          content: Text(
            hasInvite
                ? 'Você está acessando do celular e recebeu um convite para grupo. '
                    'A experiência é melhor no app. O que você prefere fazer?'
                : 'Você está acessando do celular. A experiência do Uatizapi é melhor no app. '
                    'Como você prefere continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_AppSuggestionResult.stayOnWeb),
              child: const Text('Continuar no site'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_AppSuggestionResult.goToApp),
              child: const Text('Ir para o app'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    if (result == _AppSuggestionResult.goToApp) {
      await _openNativeApp();
      return;
    }

    // Se o usuário escolheu ficar no site e há um convite, seguimos com o fluxo atual
    if (hasInvite) {
      await _showInviteDialog(roomId);
    }
  }

  Future<void> _openNativeApp() async {
    // URL scheme do app. Será tratado pelos intent-filters (Android) e URL Types (iOS).
    const appUrl = 'zapizapi://';
    final uri = Uri.parse(appUrl);

    try {
      final canOpen = await canLaunchUrl(uri);
      if (!canOpen) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível abrir o app. Verifique se ele está instalado no seu dispositivo.',
            ),
          ),
        );
        return;
      }

      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ocorreu um erro ao tentar abrir o app.'),
        ),
      );
    }
  }

  Future<void> _showInviteDialog(String roomId) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Convite para grupo'),
          content: const Text('Você recebeu um convite. Deseja entrar neste grupo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Agora não'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Entrar no grupo'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _acceptGroupInvite(roomId);
    }
  }

  Future<void> _acceptGroupInvite(String roomId) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faça login para entrar em um grupo.'),
        ),
      );
      return;
    }

    try {
      // Busca informações básicas do grupo
      final room = await Supabase.instance.client
          .from('rooms')
          .select('id, name')
          .eq('id', roomId)
          .maybeSingle();

      if (room == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Convite inválido ou grupo não encontrado.'),
          ),
        );
        return;
      }

      final name = (room['name'] as String?)?.trim() ?? 'Grupo';

      // Garante que o usuário seja membro do grupo
      final existing = await Supabase.instance.client
          .from('room_members')
          .select('room_id')
          .eq('room_id', roomId)
          .eq('user_id', currentUser.id)
          .maybeSingle();

      if (existing == null) {
        await Supabase.instance.client.from('room_members').insert({
          'room_id': roomId,
          'user_id': currentUser.id,
        });
      }

      setState(() {
        _selectedRoomId = roomId;
        _selectedRoomData = SidebarRoomData(
          id: roomId,
          title: name,
          subtitle: '',
          isDirect: false,
        );
        _sidebarReloadKey++;
      });

      // Em layout mobile abrimos a tela de chat dedicada, assim como em _SearchGroupsScreen
      final size = MediaQuery.of(context).size;
      final isMobile = size.width < 700;
      if (isMobile) {
        // ignore: use_build_context_synchronously
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _MobileChatScreen(
              title: name,
              roomId: roomId,
              roomData: _selectedRoomData,
              textController: _textController,
              inputFocus: _inputFocus,
            ),
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Você entrou no grupo "$name".'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao entrar no grupo: ${e.message}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro inesperado ao entrar no grupo: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return _buildMobileScaffold(context);
        }
        return _buildDesktopScaffold(context);
      },
    );
  }

  Scaffold _buildMobileScaffold(BuildContext context) {
    final themeController = ThemeControllerProvider.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = colorScheme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversas'),
        actions: [
          IconButton(
            tooltip: isDarkMode ? 'Tema claro' : 'Tema escuro',
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: themeController.toggle,
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await Supabase.instance.client.auth.signOut();
              await navigator.pushReplacementNamed(RoutesEnum.login.route);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: OpenConversationsSidebar(
          key: ValueKey(_sidebarReloadKey),
          width: double.infinity,
          selectedRoomId: _selectedRoomId,
          onCreateNewConversation: () async {
            await _showNewConversationDialog();
          },
          onRoomSelected: (room) {
            setState(() {
              _selectedRoomId = room.id;
              _selectedRoomData = room;
            });
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _MobileChatScreen(
                  title: room.title,
                  roomId: room.id,
                  roomData: room,
                  textController: _textController,
                  inputFocus: _inputFocus,
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nova conversa',
        onPressed: () async => _showNewConversationDialog(),
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }

  Scaffold _buildDesktopScaffold(BuildContext context) {
    final themeController = ThemeControllerProvider.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = colorScheme.brightness == Brightness.dark;
    final headerBackground = isDarkMode
        ? colorScheme.surfaceContainerHigh
        : colorScheme.primary;
    final headerForeground = isDarkMode ? colorScheme.onSurface : Colors.white;
    const sidebarWidth = 300.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: FadeTransition(
          opacity: _fadeIn,
          child: SlideTransition(
            position: _slideIn,
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      height:
                          kToolbarHeight + MediaQuery.of(context).padding.top,
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top,
                        left: sidebarWidth + 32,
                        right: 24,
                      ),
                      decoration: BoxDecoration(
                        color: headerBackground,
                        boxShadow: [
                          if (isDarkMode)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildHeaderConversationInfo(
                              context,
                              headerForeground,
                            ),
                          ),
                          Icon(
                            Icons.light_mode,
                            size: 18,
                            color: headerForeground,
                          ),
                          Switch.adaptive(
                            value: colorScheme.brightness == Brightness.dark,
                            onChanged: (_) => themeController.toggle(),
                            activeColor: isDarkMode
                                ? colorScheme.primary
                                : Colors.white,
                          ),
                          Icon(
                            Icons.dark_mode,
                            size: 18,
                            color: headerForeground,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Sair',
                            icon: Icon(Icons.logout, color: headerForeground),
                            onPressed: () async {
                              final navigator = Navigator.of(context);
                              _roomChannel?.unsubscribe();
                              await Supabase.instance.client.auth.signOut();
                              await navigator.pushReplacementNamed(
                                RoutesEnum.login.route,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: sidebarWidth + 32,
                          right: 24,
                          top: 24,
                          bottom: 24,
                        ),
                        child: Column(
                          children: [
                            ChatComponent(
                              roomId: _selectedRoomId,
                              onReplyRequested: (message) {
                                setState(() {
                                  _editingMessage = null;
                                  _replyTargetMessage = message;
                                });
                                _inputFocus.requestFocus();
                              },
                              onEditRequested: (message) {
                                setState(() {
                                  _replyTargetMessage = null;
                                  _editingMessage = message;
                                  _textController.text =
                                      (message['content'] as String?) ?? '';
                                  _textController.selection =
                                      TextSelection.collapsed(
                                          offset: _textController.text.length);
                                });
                                _inputFocus.requestFocus();
                              },
                              onDeleteRequested: (message) {
                                _confirmAndDeleteMessageForAll(
                                  context: context,
                                  message: message,
                                );
                              },
                              // Em qualquer tipo de sala (direta ou grupo),
                              // exibe o indicador visual de digitação quando
                              // algum outro usuário estiver digitando.
                              showTypingIndicator: _isPeerTyping,
                            ),
                            InputComponent(
                              controller: _textController,
                              roomId: _selectedRoomId,
                              replyToMessage: _replyTargetMessage,
                              editMessage: _editingMessage,
                              focusNode: _inputFocus,
                              onCancelReply: () {
                                setState(() {
                                  _replyTargetMessage = null;
                                });
                              },
                              onCancelEdit: () {
                                setState(() {
                                  _editingMessage = null;
                                  _textController.clear();
                                });
                              },
                              onTypingChanged: _onDesktopTypingChanged,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: sidebarWidth + 16,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top,
                        left: 16,
                        bottom: 24,
                      ),
                      child: OpenConversationsSidebar(
                        key: ValueKey(_sidebarReloadKey),
                        selectedRoomId: _selectedRoomId,
                        onCreateNewConversation: _showNewConversationDialog,
                        onRoomSelected: (room) {
                          setState(() {
                            _selectedRoomId = room.id;
                            _selectedRoomData = room;
                          });
                          _subscribeRoomChannel(room.id);
                          if (room.isDirect) {
                            _loadDirectPeerUserId(room.id);
                          } else {
                            _directPeerUserId = null;
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderConversationInfo(
    BuildContext context,
    Color headerForeground,
  ) {
    final theme = Theme.of(context);
    final selectedRoom = _selectedRoomData;

    if (selectedRoom == null) {
      return Text(
        'Selecione uma conversa',
        style: theme.textTheme.titleMedium?.copyWith(
          color: headerForeground,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    Widget? statusWidget;
    final isDirect = selectedRoom.isDirect;
    if (_isPeerTyping) {
      // Para conversas diretas e grupos, quando alguém está digitando
      // mostramos o feedback de digitação.
      statusWidget = const _TypingDots();
    } else if (isDirect) {
      final isOnline = _directPeerUserId != null &&
          _onlineUserIds.contains(_directPeerUserId);
      final dotColor =
          isOnline ? Colors.lightGreenAccent : headerForeground.withOpacity(0.6);
      final text = isOnline ? 'Online' : 'Offline';
      statusWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: headerForeground.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    final isGroup = !selectedRoom.isDirect;
    final avatar = _buildHeaderAvatar(selectedRoom, headerForeground);

    return Row(
      children: [
        if (isGroup)
          InkWell(
            onTap: () {
              showGroupDetailsBottomSheet(
                context,
                roomId: selectedRoom.id,
                roomName: selectedRoom.title,
                avatarUrl: selectedRoom.avatarUrl,
              );
            },
            customBorder: const CircleBorder(),
            child: avatar,
          )
        else
          avatar,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selectedRoom.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: headerForeground,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (statusWidget != null) ...[
                const SizedBox(height: 2),
                DefaultTextStyle(
                  style: theme.textTheme.labelSmall?.copyWith(
                        color: headerForeground.withOpacity(0.85),
                      ) ??
                      TextStyle(color: headerForeground.withOpacity(0.85)),
                  child: statusWidget,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderAvatar(SidebarRoomData room, Color headerForeground) {
    final avatarBackground = headerForeground.withOpacity(0.2);

    if (room.isDirect) {
      final avatarUrl = room.avatarUrl?.trim();
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        return CircleAvatar(
          radius: 20,
          backgroundColor: avatarBackground,
          child: ClipOval(
            child: Image.network(
              avatarUrl,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.person_outline,
                color: headerForeground,
              ),
            ),
          ),
        );
      }

      return CircleAvatar(
        radius: 20,
        backgroundColor: avatarBackground,
        child: Icon(
          Icons.person_outline,
          color: headerForeground,
        ),
      );
    } else {
      final avatarUrl = room.avatarUrl?.trim();
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        return CircleAvatar(
          radius: 20,
          backgroundColor: avatarBackground,
          child: ClipOval(
            child: Image.network(
              avatarUrl,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.group_outlined,
                color: headerForeground,
              ),
            ),
          ),
        );
      }

      return CircleAvatar(
        radius: 20,
        backgroundColor: avatarBackground,
        child: Icon(
          Icons.group_outlined,
          color: headerForeground,
        ),
      );
    }
  }

  Future<void> _showNewConversationDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Conversa direta'),
              subtitle: const Text('Inicie um bate-papo 1:1'),
              onTap: () async {
                Navigator.of(context).pop();
                if (!mounted) {
                  return;
                }
                await _showDirectConversationDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Criar grupo'),
              subtitle: const Text('Escolha participantes e visibilidade'),
              onTap: () async {
                Navigator.of(context).pop();
                if (!mounted) {
                  return;
                }
                await _showGroupConversationDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Pesquisar grupos'),
              subtitle: const Text('Veja e entre em grupos pesquisáveis'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _SearchGroupsScreen(
                      onEnterRoom: (roomId, title) {
                        setState(() {
                          _selectedRoomId = roomId;
                          _selectedRoomData = SidebarRoomData(
                            id: roomId,
                            title: title,
                            subtitle: '',
                            isDirect: false,
                          );
                        });
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _MobileChatScreen(
                              title: title,
                              roomId: roomId,
                              roomData: _selectedRoomData,
                              textController: _textController,
                              inputFocus: _inputFocus,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Future<void> _showDirectConversationDialog() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var isLoading = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              setDialogState(() {
                isLoading = true;
              });

              try {
                final roomRepository = RoomRepositoryImplementation(
                  roomService: RoomService(),
                  profileRepository: ProfileRepositoryImplementation(
                    profileService: ProfileService(),
                  ),
                );

                final roomId = await roomRepository.createDirectRoomByEmail(
                  emailController.text,
                );

                if (!mounted) {
                  return;
                }

                setState(() {
                  _selectedRoomId = roomId;
                  _selectedRoomData = null;
                });
                _subscribeRoomChannel(roomId);
                _directPeerUserId = null;

                Navigator.of(dialogContext).pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Conversa iniciada com sucesso.'),
                  ),
                );
              } catch (error) {
                setDialogState(() {
                  isLoading = false;
                });

                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(_mapErrorMessage(error)),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Nova conversa'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: emailController,
                  enabled: !isLoading,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail do usuário',
                    hintText: 'usuario@exemplo.com',
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return 'Informe um e-mail.';
                    }
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailRegex.hasMatch(email)) {
                      return 'Informe um e-mail válido.';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : submit,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Iniciar'),
                ),
              ],
            );
          },
        );
      },
    );

    emailController.dispose();
  }

  Future<void> _showGroupConversationDialog() async {
    final nameController = TextEditingController();
    final emailsController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Faça login novamente para criar um grupo.'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var isLoading = false;
        var isSearchable = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              final emails = emailsController.text
                  .split(RegExp(r'[,\n;\s]+'))
                  .map((email) => email.trim().toLowerCase())
                  .where((email) => email.isNotEmpty)
                  .toSet()
                  .toList();

              if (emails.isEmpty) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Informe ao menos um e-mail válido para adicionar ao grupo.',
                    ),
                  ),
                );
                return;
              }

              setDialogState(() {
                isLoading = true;
              });

              try {
                final profileRepository = ProfileRepositoryImplementation(
                  profileService: ProfileService(),
                );
                final roomRepository = RoomRepositoryImplementation(
                  roomService: RoomService(),
                  profileRepository: profileRepository,
                );

                final memberIds = <String>{currentUser.id};

                for (final email in emails) {
                  final userId = await profileRepository.getUserIdByEmail(
                    email,
                  );
                  memberIds.add(userId);
                }

                final roomId = await roomRepository.createGroupRoom(
                  name: nameController.text.trim(),
                  memberIds: memberIds.toList(),
                  isSearchable: isSearchable,
                );

                if (!mounted) {
                  return;
                }

                setState(() {
                  _selectedRoomId = roomId;
                  _selectedRoomData = null;
                });
                _subscribeRoomChannel(roomId);
                _directPeerUserId = null;

                Navigator.of(dialogContext).pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Grupo criado com sucesso.'),
                  ),
                );
              } catch (error) {
                setDialogState(() {
                  isLoading = false;
                });
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(_mapErrorMessage(error)),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Criar novo grupo'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        enabled: !isLoading,
                        decoration: const InputDecoration(
                          labelText: 'Nome do grupo',
                          hintText: 'Ex: Squad Flutter',
                        ),
                        validator: (value) {
                          final name = value?.trim() ?? '';
                          if (name.isEmpty) {
                            return 'Informe um nome para o grupo.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailsController,
                        enabled: !isLoading,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Participantes',
                          hintText:
                              'Digite e-mails separados por vírgula ou quebra de linha',
                        ),
                        validator: (value) {
                          final emails = value ?? '';
                          if (emails.trim().isEmpty) {
                            return 'Informe ao menos um participante.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: isSearchable,
                        onChanged: isLoading
                            ? null
                            : (value) {
                                setDialogState(() {
                                  isSearchable = value;
                                });
                              },
                        title: const Text(
                          'Permitir que o grupo seja pesquisável',
                        ),
                        subtitle: const Text(
                          'Outros usuários poderão encontrar este grupo ao buscar pelo nome.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : submit,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Criar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailsController.dispose();
  }

  String _mapErrorMessage(Object error) {
    if (error is ProfileServiceException) {
      return error.message;
    }
    if (error is RoomServiceException) {
      return error.message;
    }
    return 'Não foi possível iniciar a conversa. Tente novamente.';
  }

  void _subscribeRoomChannel(String roomId) {
    _typingResetTimer?.cancel();
    _roomChannel?.unsubscribe();
    _isPeerOnline = false;
    _isPeerTyping = false;
    setState(() {});

    final channel = Supabase.instance.client.channel('room:$roomId', opts: const RealtimeChannelConfig(self: true));
    channel.onPresenceSync((_) {
      debugPrint('[presence][room:$roomId] sync');
      _updatePresenceStateDesktop(channel);
    });
    channel.onPresenceJoin((_) {
      debugPrint('[presence][room:$roomId] join');
      _updatePresenceStateDesktop(channel);
    });
    channel.onPresenceLeave((_) {
      debugPrint('[presence][room:$roomId] leave');
      _updatePresenceStateDesktop(channel);
    });
    channel.onBroadcast(
      event: 'typing',
      callback: (dynamic payload, [ref]) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        final from = (payload is Map<String, dynamic> ? payload['user_id'] : null) as String? ?? '';
        final isTyping = (payload is Map<String, dynamic>) && payload['is_typing'] == true;
        if (from.isNotEmpty && from != currentUserId) {
          if (_isPeerTyping != isTyping) {
            setState(() {
              _isPeerTyping = isTyping;
            });
          }
          _typingResetTimer?.cancel();
          if (isTyping) {
            _typingResetTimer = Timer(const Duration(milliseconds: 1500), () {
              if (mounted) {
                if (_isPeerTyping) {
                  setState(() {
                    _isPeerTyping = false;
                  });
                }
              }
            });
          }
        }
      },
    );
    channel.subscribe((status, [ref]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        await channel.track({'user_id': currentUserId});
        debugPrint('[presence][room:$roomId] subscribed + tracked user_id=$currentUserId');
        _updatePresenceStateDesktop(channel);
      }
    });
    _roomChannel = channel;
  }

  void _updatePresenceStateDesktop(RealtimeChannel channel) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final dynamic state = channel.presenceState();
    debugPrint('[presence][room] raw_state=$state');
    final presentIds = _extractUserIdsFromPresenceState(state);
    presentIds.remove(currentUserId);
    final newOnline = presentIds.isNotEmpty;
    debugPrint('[presence][room] state_ids=${presentIds.toList()} newOnline=$newOnline');
    if (newOnline != _isPeerOnline) {
      setState(() {
        _isPeerOnline = newOnline;
      });
    }
  }

  void _onDesktopTypingChanged(bool isTyping) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _roomChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': currentUserId, 'is_typing': isTyping},
    );
  }

  Future<void> _loadDirectPeerUserId(String roomId) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;
      final response = await Supabase.instance.client
          .from('room_members')
          .select('user_id')
          .eq('room_id', roomId)
          .neq('user_id', currentUserId);
      final list = (response as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
      final other = list.isNotEmpty ? (list.first['user_id'] as String?) : null;
      if (other != null && other.isNotEmpty) {
        setState(() {
          _directPeerUserId = other;
        });
      } else {
        setState(() {
          _directPeerUserId = null;
        });
      }
    } catch (_) {
      setState(() {
        _directPeerUserId = null;
      });
    }
  }

  void _subscribeGlobalPresence() {
    _globalPresenceChannel?.unsubscribe();
    _onlineUserIds.clear();
    final channel = Supabase.instance.client
        .channel('online', opts: const RealtimeChannelConfig(self: true));
    void update() {
      final state = channel.presenceState();
      debugPrint('[presence][global] raw_state=$state');
      final ids = _extractUserIdsFromPresenceState(state);
      setState(() {
        _onlineUserIds
          ..clear()
          ..addAll(ids);
      });
      debugPrint('[presence][global] online_ids=${ids.toList()}');
    }
    channel.onPresenceSync((_) {
      debugPrint('[presence][global] sync');
      update();
    });
    channel.onPresenceJoin((_) {
      debugPrint('[presence][global] join');
      update();
    });
    channel.onPresenceLeave((_) {
      debugPrint('[presence][global] leave');
      update();
    });
    channel.subscribe((status, [ref]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null) {
          await channel.track({'user_id': currentUserId});
          debugPrint(
              '[presence][global] subscribed + tracked user_id=$currentUserId');
        } else {
          debugPrint(
              '[presence][global] subscribed but no authenticated user to track');
        }
        update();
      }
    });
    _globalPresenceChannel = channel;
  }
}

/// Exibe um bottom sheet com detalhes do grupo: membros, link de convite e
/// ações para adicionar pessoas e alterar a foto do grupo.
Future<void> showGroupDetailsBottomSheet(
  BuildContext context, {
  required String roomId,
  required String roomName,
  String? avatarUrl,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GroupDetailsSheet(
      roomId: roomId,
      roomName: roomName,
      initialAvatarUrl: avatarUrl,
    ),
  );
}

class _GroupDetailsSheet extends StatefulWidget {
  const _GroupDetailsSheet({
    required this.roomId,
    required this.roomName,
    this.initialAvatarUrl,
  });

  final String roomId;
  final String roomName;
  final String? initialAvatarUrl;

  @override
  State<_GroupDetailsSheet> createState() => _GroupDetailsSheetState();
}

class _GroupDetailsSheetState extends State<_GroupDetailsSheet> {
  late Future<List<Map<String, dynamic>>> _membersFuture;
  String? _avatarUrl;
  bool _isUpdatingAvatar = false;
  bool _isAddingMember = false;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.initialAvatarUrl?.trim();
    _membersFuture = _fetchMembers();
  }

  Future<List<Map<String, dynamic>>> _fetchMembers() async {
    final response = await Supabase.instance.client
        .from('room_members')
        .select(
          'profiles ( full_name, email, avatar_url )',
        )
        .eq('room_id', widget.roomId);

    final list = (response as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const [];
    return list;
  }

  Future<void> _copyInviteLink() async {
    // TODO: Ajuste o domínio/base do link conforme o ambiente da aplicação.
    final inviteLink = '${dotenv.env['BASE_URL']}/invite?room=${widget.roomId}';
    await Clipboard.setData(ClipboardData(text: inviteLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link de convite copiado.')),
    );
  } 

  Future<void> _addMember() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar integrante'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-mail do integrante',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return 'Informe o e-mail do integrante.';
                    }
                    if (!email.contains('@')) {
                      return 'Informe um e-mail válido.';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isAddingMember
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: _isAddingMember
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          final email = emailController.text.trim();
                          if (email.isEmpty) return;

                          setDialogState(() {
                            _isAddingMember = true;
                          });

                          try {
                            final profileRepository =
                                ProfileRepositoryImplementation(
                              profileService: ProfileService(),
                            );
                            final userId = await profileRepository
                                .getUserIdByEmail(email);

                            await Supabase.instance.client
                                .from('room_members')
                                .insert({
                              'room_id': widget.roomId,
                              'user_id': userId,
                            });

                            if (!mounted) return;
                            setState(() {
                              _membersFuture = _fetchMembers();
                            });

                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Integrante adicionado com sucesso.',
                                ),
                              ),
                            );
                          } on PostgrestException catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao adicionar integrante: ${e.message}',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro inesperado ao adicionar integrante: $e',
                                ),
                              ),
                            );
                          } finally {
                            if (mounted) {
                              setDialogState(() {
                                _isAddingMember = false;
                              });
                            }
                          }
                        },
                  child: _isAddingMember
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _changeGroupAvatar() async {
    if (_isUpdatingAvatar) return;
    setState(() {
      _isUpdatingAvatar = true;
    });
    try {
      final avatarService = AvatarService();
      final upload = await avatarService.pickAndUploadGroupAvatar(
        roomId: widget.roomId,
      );
      if (upload == null) {
        setState(() {
          _isUpdatingAvatar = false;
        });
        return;
      }

      await Supabase.instance.client
          .from('rooms')
          .update({'avatar_url': upload.url}).eq('id', widget.roomId);

      if (!mounted) return;
      setState(() {
        _avatarUrl = upload.url;
        _isUpdatingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto do grupo atualizada.')),
      );
    } on AvatarServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdatingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdatingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar avatar do grupo: ${e.message}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdatingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro inesperado ao atualizar avatar: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final avatarWidget = CircleAvatar(
      radius: 40,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: _avatarUrl != null && _avatarUrl!.isNotEmpty
          ? ClipOval(
              child: Image.network(
                _avatarUrl!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.group_outlined,
                  color: scheme.onSecondaryContainer,
                  size: 40,
                ),
              ),
            )
          : Icon(
              Icons.group_outlined,
              color: scheme.onSecondaryContainer,
              size: 40,
            ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  avatarWidget,
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: _isUpdatingAvatar ? null : _changeGroupAvatar,
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        child: _isUpdatingAvatar
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.photo_camera_outlined,
                                size: 16,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.roomName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${widget.roomId.substring(0, 8)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyInviteLink,
                  icon: const Icon(Icons.link),
                  label: const Text('Copiar convite'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addMember,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Adicionar pessoa'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Integrantes',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 360,
            ),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _membersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Erro ao carregar integrantes: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final members = snapshot.data ?? const [];
                if (members.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nenhum integrante encontrado.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = members[index];
                    final profile =
                        item['profiles'] as Map<String, dynamic>? ?? {};
                    final fullName =
                        (profile['full_name'] as String?)?.trim() ?? '';
                    final email =
                        (profile['email'] as String?)?.trim() ?? '';
                    final displayName = fullName.isNotEmpty
                        ? fullName
                        : (email.isNotEmpty
                            ? email.split('@').first
                            : 'Usuário');

                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(displayName),
                      subtitle: email.isNotEmpty ? Text(email) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Componente de chat
class ChatComponent extends StatefulWidget {
  /// Construtor da classe [ChatComponent]
  const ChatComponent({
    required this.roomId,
    this.onReplyRequested,
    this.onEditRequested,
    this.onDeleteRequested,
    this.onMessageTap,
    this.onMessageLongPress,
    this.selectedMessageId,
    this.showTypingIndicator = false,
    super.key,
  });

  /// Identificador da sala selecionada.
  final String? roomId;
  /// Callback ao pedir resposta a uma mensagem.
  final ValueChanged<Map<String, dynamic>>? onReplyRequested;
  /// Callback ao pedir edição de uma mensagem.
  final ValueChanged<Map<String, dynamic>>? onEditRequested;
  /// Callback ao pedir remoção definitiva da mensagem para todos.
  final ValueChanged<Map<String, dynamic>>? onDeleteRequested;
  /// Callback ao tocar na mensagem (para alternar seleção, etc.)
  final ValueChanged<Map<String, dynamic>>? onMessageTap;
  /// Callback para long press (mobile) para selecionar a mensagem e mostrar ações no header.
  final ValueChanged<Map<String, dynamic>>? onMessageLongPress;
  /// Exibe um item visual de "digitando..." no final da lista.
  final bool showTypingIndicator;
  /// Id da mensagem selecionada (para feedback visual)
  final String? selectedMessageId;

  @override
  State<ChatComponent> createState() => _ChatComponentState();
}

class _ChatComponentState extends State<ChatComponent> {
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;
  int _lastReactionsCount = 0;
  Stream<List<Map<String, dynamic>>>? _messagesStream;
  Stream<List<Map<String, dynamic>>>? _reactionsStream;
  // Snapshot local usado como fallback para garantir atualização imediata
  // das reações após um toggle, mesmo que o stream do Supabase não dispare.
  List<Map<String, dynamic>>? _reactionsSnapshotOverride;
  String? _hoveredMessageId;
  final Map<String, double> _bubbleWidthByMessageId = {};
  String? _activeMenuMessageId;

  bool _lastTypingVisible = false;
  double _lastBottomInset = 0;

  @override
  void initState() {
    super.initState();
    _messagesStream = _createMessagesStream(widget.roomId);
    _reactionsStream = _createReactionsStream(widget.roomId);
    _lastTypingVisible = widget.showTypingIndicator;
  }

  Stream<List<Map<String, dynamic>>>? _createMessagesStream(String? roomId) {
    if (roomId == null) {
      return null;
    }
    return Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: true);
  }

  Stream<List<Map<String, dynamic>>>? _createReactionsStream(String? roomId) {
    if (roomId == null) return null;
    return Supabase.instance.client
        .from('message_reactions')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId);
  }

  @override
  void didUpdateWidget(covariant ChatComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomId != oldWidget.roomId) {
      _lastMessageCount = 0;
      _lastReactionsCount = 0;
      _reactionsSnapshotOverride = null;
      _messagesStream = _createMessagesStream(widget.roomId);
      _reactionsStream = _createReactionsStream(widget.roomId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    }
    if (widget.showTypingIndicator != _lastTypingVisible) {
      _lastTypingVisible = widget.showTypingIndicator;
      if (_lastTypingVisible) {
        _scheduleScrollToBottom();
      }
    }
  }

  /// Recarrega manualmente as reações da sala informada e armazena um
  /// snapshot local para forçar a atualização visual imediata.
  Future<void> _reloadReactionsForRoom(String roomId) async {
    try {
      final response = await Supabase.instance.client
          .from('message_reactions')
          .select()
          .eq('room_id', roomId);
      if (!mounted) return;
      final list = (response as List)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      setState(() {
        _reactionsSnapshotOverride = list;
      });
    } catch (e) {
      debugPrint('Erro ao recarregar reações: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  bool _isNearBottom({double threshold = 64}) {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    final diff = position.maxScrollExtent - position.pixels;
    return diff <= threshold;
  }

  @override
  Widget build(BuildContext context) {
    // Quando o teclado abre no mobile (viewInsets.bottom > 0),
    // garantimos que a lista role até o final para que as últimas
    // mensagens continuem visíveis.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset > 0 && bottomInset != _lastBottomInset) {
      _scheduleScrollToBottom();
    }
    _lastBottomInset = bottomInset;

    final roomId = widget.roomId;
    if (roomId == null) {
      return const Expanded(
        child: Center(
          child: Text('Selecione uma conversa para visualizar as mensagens'),
        ),
      );
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Expanded(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _messagesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ChatSkeleton();
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Erro ao carregar mensagens: ${snapshot.error}'),
            );
          }

          final messages = snapshot.data;

          if (messages == null || messages.isEmpty) {
            _lastMessageCount = 0;
            return const Center(child: Text('Nenhuma mensagem nesta conversa'));
          }

          if (messages.length != _lastMessageCount) {
            final isFirstLoad = _lastMessageCount == 0;
            _lastMessageCount = messages.length;
            _scheduleScrollToBottom(animated: !isFirstLoad);
          }

          final scheme = Theme.of(context).colorScheme;
          final byId = <String, Map<String, dynamic>>{
            for (final m in messages) (m['id'] as String): m
          };

          final extra = widget.showTypingIndicator ? 1 : 0;
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _reactionsStream,
            builder: (context, reactionsSnap) {
              // Se tivermos um snapshot local, ele tem prioridade para
              // garantir que o toggle apareça imediatamente.
              final reactions = _reactionsSnapshotOverride ??
                  reactionsSnap.data ??
                  const <Map<String, dynamic>>[];
              final reactionsCount = reactions.length;
              final bool shouldStickToBottom =
                  reactionsCount != _lastReactionsCount && _isNearBottom();
              _lastReactionsCount = reactionsCount;
              if (shouldStickToBottom) {
                _scheduleScrollToBottom(animated: false);
              }
              final countsByMessage = <String, Map<String, int>>{};
              final myReactsKey = <String>{}; // "$messageId|$emoji"
              for (final r in reactions) {
                final mid = r['message_id'] as String?;
                final emoji = r['emoji'] as String?;
                final uid = r['user_id'] as String?;
                if (mid == null || emoji == null) continue;
                countsByMessage.putIfAbsent(mid, () => <String, int>{});
                countsByMessage[mid]![emoji] =
                    (countsByMessage[mid]![emoji] ?? 0) + 1;
                if (uid != null && uid == currentUserId) {
                  myReactsKey.add('$mid|$emoji');
                }
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: messages.length + extra,
                itemBuilder: (context, index) {
                  if (extra == 1 && index == messages.length) {
                    return const _TypingMessageBubble();
                  }
          final message = messages[index];
          final isMine = message['from_id'] == currentUserId;
          final content = message['content'] as String? ?? '';
          final author = message['from_name'] as String? ?? 'Sem nome';
          final messageId = message['id'] as String?;
          final parentId = message['parent_id'] as String?;
          final editedAt = message['edited_at'];
          final isDeleted = (message['is_deleted'] as bool?) ?? false;

                  // Regra de edição: somente o autor pode editar e apenas até 15 minutos após o envio
                  final createdAtRaw = message['created_at'];
                  DateTime? createdAt;
                  if (createdAtRaw is String) {
                    createdAt = DateTime.tryParse(createdAtRaw);
                  } else if (createdAtRaw is DateTime) {
                    createdAt = createdAtRaw;
                  }
                  final createdAtUtc = createdAt?.toUtc();
                  final nowUtc = DateTime.now().toUtc();
                  final canEdit = isMine &&
                      createdAtUtc != null &&
                      nowUtc.difference(createdAtUtc).inMinutes < 15;

                  // Medir largura da bolha para posicionar dinamicamente o menu
                  final bubbleKey = GlobalKey();
                  final isSelected =
                      messageId != null && widget.selectedMessageId == messageId;
                  if (messageId != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final context = bubbleKey.currentContext;
                      final size = context?.size;
                      if (size != null) {
                        final width = size.width;
                        if (_bubbleWidthByMessageId[messageId] != width && mounted) {
                          setState(() {
                            _bubbleWidthByMessageId[messageId] = width;
                          });
                        }
                      }
                    });
                  }
                  const double menuSpacing = 8;
          final menuOffset = ((messageId != null
                              ? _bubbleWidthByMessageId[messageId]
                              : null) ??
                          0) +
                      menuSpacing;

                  final counts = messageId != null
                      ? (countsByMessage[messageId] ?? const <String, int>{})
                      : const <String, int>{};

          Widget? replyPreview;
          if (!isDeleted &&
              parentId != null &&
              byId.containsKey(parentId)) {
            final parent = byId[parentId]!;
            final parentAuthor =
                (parent['from_name'] as String?) ?? 'Sem nome';
            final parentContent = (parent['content'] as String?) ?? '';
            replyPreview = Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color:
                    scheme.surfaceContainerHighest.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 3,
                    height: 28,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Em resposta a $parentAuthor',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          parentContent,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: MouseRegion(
                      onEnter: (_) {
                        if (messageId != null) {
                          setState(() => _hoveredMessageId = messageId);
                        }
                      },
                      onExit: (_) {
                        if (_activeMenuMessageId == null &&
                            _hoveredMessageId == messageId) {
                          setState(() => _hoveredMessageId = null);
                        }
                      },
                      child: SizedBox(
                        width: double.infinity,
                        child: Align(
                          alignment: isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: isMine ? 56 : 0,
                              right: isMine ? 0 : 56,
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Align(
                                  alignment: isMine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    key: bubbleKey,
                                    constraints:
                                        const BoxConstraints(maxWidth: 260),
                                    child: GestureDetector(
                                onTap: () {
                                  if (widget.onMessageTap != null) {
                                    widget.onMessageTap!(message);
                                  }
                                },
                                onLongPress: () {
                                  if (!isDeleted &&
                                      widget.onMessageLongPress != null) {
                                    widget.onMessageLongPress!(message);
                                  }
                                },
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: isMine
                                          ? scheme.primaryContainer
                                          : scheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? scheme.primary
                                            : (isMine
                                                ? Colors.transparent
                                                : scheme.outlineVariant),
                                        width: isSelected ? 2 : 1,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: scheme.primary
                                                    .withOpacity(0.18),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ]
                                          : const [],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment: isMine
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          if (!isMine)
                                            Text(
                                              author,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600),
                                            ),
                                          ?replyPreview,
                                          if (isDeleted)
                                            Text(
                                              'Mensagem apagada',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontStyle: FontStyle.italic,
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.color
                                                        ?.withOpacity(0.7),
                                                  ),
                                            )
                                          else if (_isImageUrl(content))
                                            _MessageImage(
                                              url: content,
                                              onTap: () => _openImageViewer(
                                                  context, content),
                                            )
                                          else if (_isUrl(content))
                                            InkWell(
                                              onTap: () => _openUrl(content),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.attach_file,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      _fileNameFromUrl(content),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                              decoration:
                                                                  TextDecoration
                                                                      .underline),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      maxLines: 2,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            Text(
                                              content,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                          if (!isDeleted && editedAt != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 6),
                                              child: Text(
                                                '(editada)',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall,
                                              ),
                                            ),
                                          if (!isDeleted &&
                                              messageId != null &&
                                              counts.isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children:
                                                    counts.entries.map((e) {
                                                  final emoji = e.key;
                                                  final total = e.value;
                                                  final reacted = myReactsKey
                                                      .contains(
                                                          '$messageId|$emoji');
                                                  return InkWell(
                                                    onTap: () =>
                                                        _toggleReaction(
                                                      messageId,
                                                      roomId,
                                                      emoji,
                                                    ),
                                                    borderRadius:
                                                        const BorderRadius.all(
                                                            Radius.circular(
                                                                999)),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: reacted
                                                            ? scheme.primary
                                                                .withOpacity(
                                                                    0.25)
                                                            : scheme
                                                                .surfaceContainerHighest
                                                                .withOpacity(
                                                                    0.4),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(999),
                                                        border: Border.all(
                                                          color: reacted
                                                              ? scheme.primary
                                                              : scheme
                                                                  .outlineVariant,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(emoji),
                                                          const SizedBox(
                                                              width: 4),
                                                          Text(
                                                            '$total',
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .labelSmall,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                ),
                              ),
                               if (!isDeleted &&
                                   (_hoveredMessageId == messageId ||
                                       _activeMenuMessageId == messageId))
                                 Positioned(
                                   top: 0,
                                   bottom: 0,
                                   left: isMine ? null : menuOffset,
                                   right: isMine ? menuOffset : null,
                                   child: Center(
                                     child: Container(
                                       decoration: BoxDecoration(
                                         color: scheme.surfaceContainerHighest
                                             .withOpacity(0.6),
                                         shape: BoxShape.circle,
                                       ),
                                       child: PopupMenuButton<String>(
                                         tooltip: 'Mais opções',
                                         icon: const Icon(
                                           Icons.more_vert,
                                           size: 18,
                                         ),
                                         onOpened: () {
                                           if (_activeMenuMessageId != messageId) {
                                             setState(() {
                                               _activeMenuMessageId = messageId;
                                             });
                                           }
                                         },
                                         onCanceled: () {
                                           if (_activeMenuMessageId != null) {
                                             setState(() {
                                               _activeMenuMessageId = null;
                                               _hoveredMessageId = null;
                                             });
                                           }
                                         },
                                         onSelected: (value) {
                                           if (value == 'reply') {
                                             widget.onReplyRequested?.call(message);
                                           } else if (value == 'edit') {
                                             widget.onEditRequested?.call(message);
                                           } else if (value == 'react' &&
                                               messageId != null) {
                                             _showEmojiPicker(
                                                 context, messageId, roomId);
                                          } else if (value == 'delete') {
                                            widget.onDeleteRequested
                                                ?.call(message);
                                           }
                                           if (_activeMenuMessageId != null) {
                                             setState(() {
                                               _activeMenuMessageId = null;
                                               _hoveredMessageId = null;
                                             });
                                           }
                                         },
                                         itemBuilder: (context) {
                                           final entries =
                                               <PopupMenuEntry<String>>[
                                             const PopupMenuItem<String>(
                                               value: 'reply',
                                               child: Text('Responder'),
                                             ),
                                             const PopupMenuItem<String>(
                                               value: 'react',
                                               child: Text('Reagir'),
                                             ),
                                           ];
                                           if (canEdit) {
                                             entries.insert(
                                               1,
                                               const PopupMenuItem<String>(
                                                 value: 'edit',
                                                 child: Text('Editar'),
                                               ),
                                             );
                                            }
                                            if (isMine) {
                                              entries.add(
                                                const PopupMenuItem<String>(
                                                  value: 'delete',
                                                  child:
                                                      Text('Apagar para todos'),
                                                ),
                                              );
                                           }
                                           return entries;
                                         },
                                       ),
                                     ),
                                   ),
                                 ),
                            ],
                          ),
                            ),
                          ),
                        ),
                      ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _toggleReaction(
    String messageId,
    String roomId,
    String emoji,
  ) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;
    try {
      final existing = await Supabase.instance.client
          .from('message_reactions')
          .select('id')
          .eq('message_id', messageId)
          .eq('user_id', currentUserId)
          .eq('emoji', emoji)
          .maybeSingle();

      if (existing != null && existing.isNotEmpty) {
        final id = existing['id'] as String?;
        if (id != null) {
          await Supabase.instance.client
              .from('message_reactions')
              .delete()
              .eq('id', id);
        }
      } else {
        await Supabase.instance.client.from('message_reactions').insert({
          'message_id': messageId,
          'room_id': roomId,
          'user_id': currentUserId,
          'emoji': emoji,
        });
      }
      // Garante que a UI reflita imediatamente o estado mais recente,
      // mesmo se o stream de Realtime não estiver disparando corretamente.
      await _reloadReactionsForRoom(roomId);
    } catch (e) {
      debugPrint('Erro ao alternar reação: $e');
    }
  }

  Future<void> _showEmojiPicker(
    BuildContext context,
    String messageId,
    String roomId,
  ) async {
    const emojis = [
      '😀','😂','😍','👍','👎','🙏','🔥','🎉','😮','😢','😡','🤔',
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: emojis.map((e) {
              return InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleReaction(messageId, roomId, e);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(
                    e,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _MessageImage extends StatelessWidget {
  const _MessageImage({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: url,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(
              'Falha ao carregar imagem',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
}

bool _isUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  return uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

bool _isImageUrl(String value) {
  if (!_isUrl(value)) return false;
  final lower = value.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.contains('image=');
}

String _fileNameFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final path = uri.path;
    if (path.isEmpty) return url;
    final segments = path.split('/');
    return segments.isNotEmpty ? segments.last : url;
  } catch (_) {
    return url;
  }
}

/// Extrai todos os user_ids presentes em qualquer formato de presenceState.
Set<String> _extractUserIdsFromPresenceState(dynamic state) {
  final result = <String>{};
  if (state is Map) {
    state.forEach((key, single) {
      // Algumas implementações usam a própria chave do mapa como presence key (user_id)
      if (key is String && key.isNotEmpty) {
        result.add(key);
      }
      // Case A: Presence com propriedade `.metas`
      try {
        final metas = (single as dynamic).metas as List?;
        if (metas != null) {
          for (final m in metas) {
            if (m is Map) {
              final uid = m['user_id'] ??
                  (m['payload'] is Map ? (m['payload'] as Map)['user_id'] : null);
              if (uid is String && uid.isNotEmpty) {
                result.add(uid);
              }
            }
          }
          return;
        }
      } catch (_) {
        // continuar para Case B
      }
      // Case B: Lista direta de metas ou objetos similares
      if (single is List) {
        for (final m in single) {
          if (m is Map) {
            // às vezes as metas estão aninhadas
            final nested = m['metas'];
            if (nested is List && nested.isNotEmpty) {
              for (final mm in nested) {
                if (mm is Map) {
                  final uid = mm['user_id'] ??
                      (mm['payload'] is Map ? (mm['payload'] as Map)['user_id'] : null);
                  if (uid is String && uid.isNotEmpty) {
                    result.add(uid);
                  }
                }
              }
            } else {
              final uid = m['user_id'] ??
                  (m['payload'] is Map ? (m['payload'] as Map)['user_id'] : null);
              if (uid is String && uid.isNotEmpty) {
                result.add(uid);
              }
            }
          }
        }
      } else if (single is Map) {
        // Case C: Busca profunda por qualquer 'user_id' em mapas aninhados
        _deepCollectUserIds(single, result);
      }
    });
  } else if (state is List) {
    // Supabase Flutter pode retornar uma lista de PresenceState com .presences contendo Presence com .payload
    try {
      for (final s in state) {
        final dynamic d = s;
        final presences = d.presences as List?;
        if (presences != null) {
          for (final p in presences) {
            final payload = (p as dynamic).payload;
            if (payload is Map) {
              final uid = payload['user_id'];
              if (uid is String && uid.isNotEmpty) {
                result.add(uid);
              }
            }
          }
        }
      }
      return result;
    } catch (_) {
      // Se a API mudar, faz uma busca profunda em qualquer estrutura interna
      _deepCollectUserIds(state, result);
    }
  }
  return result;
}

void _deepCollectUserIds(dynamic node, Set<String> acc) {
  if (node is Map) {
    node.forEach((key, value) {
      if (key == 'user_id' && value is String && value.isNotEmpty) {
        acc.add(value);
      } else {
        _deepCollectUserIds(value, acc);
      }
    });
  } else if (node is List) {
    for (final item in node) {
      _deepCollectUserIds(item, acc);
    }
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> {
  late Timer _timer;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() {
        _count = (_count + 1) % 4;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const base = 'Digitando';
    final dots = '.' * _count;
    return Text('$base$dots');
  }
}

class _TypingMessageBubble extends StatefulWidget {
  const _TypingMessageBubble();

  @override
  State<_TypingMessageBubble> createState() => _TypingMessageBubbleState();
}

class _TypingMessageBubbleState extends State<_TypingMessageBubble> {
  late Timer _timer;
  int _phase = 0; // 0,1,2

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        _phase = (_phase + 1) % 3;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final active = i == _phase;
                  return Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: active ? 0.35 : 0.15,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

void _openImageViewer(BuildContext context, String url) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) => ImageViewer(imageUrl: url, heroTag: url),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        );
      },
    ),
  );
}

/// Componente de entrada
class InputComponent extends StatefulWidget {
  /// Construtor da classe [InputComponent]
  const InputComponent({
    required this.controller,
    required this.roomId,
    this.replyToMessage,
    this.editMessage,
    this.onCancelReply,
    this.onCancelEdit,
    this.onTypingChanged,
    this.focusNode,
    super.key,
  });

  /// Controlador de texto
  final TextEditingController controller;

  /// Sala selecionada para envio
  final String? roomId;

  /// Mensagem alvo para resposta
  final Map<String, dynamic>? replyToMessage;
  /// Mensagem alvo para edição
  final Map<String, dynamic>? editMessage;
  /// Cancelar estado de resposta
  final VoidCallback? onCancelReply;
  /// Cancelar estado de edição
  final VoidCallback? onCancelEdit;

  /// Callback para notificar alterações de digitação (true = digitando)
  final ValueChanged<bool>? onTypingChanged;
  /// Focus node externo para controlar foco do campo
  final FocusNode? focusNode;

  @override
  State<InputComponent> createState() => _InputComponentState();
}

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class _InsertNewLineIntent extends Intent {
  const _InsertNewLineIntent();
}

class _InputComponentState extends State<InputComponent> {
  bool _isSending = false;
  late final FocusNode _inputFocus;
  bool _ownsFocusNode = false;
  final AttachmentService _attachmentService = AttachmentService();
  Timer? _typingDebounce;
  bool _isCurrentlyTyping = false;
  Timer? _typingPingTimer;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _inputFocus = widget.focusNode!;
      _ownsFocusNode = false;
    } else {
      _inputFocus = FocusNode();
      _ownsFocusNode = true;
    }
    widget.controller.addListener(_onTextChanged);
    _inputFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _typingPingTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _inputFocus.removeListener(_onFocusChanged);
    if (_ownsFocusNode) {
      _inputFocus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.roomId != null && !_isSending;

    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.editMessage != null || widget.replyToMessage != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (widget.editMessage != null) {
                        return Text(
                          'Editando mensagem',
                          style: Theme.of(context).textTheme.labelMedium,
                        );
                      }
                      final msg = widget.replyToMessage!;
                      final author =
                          (msg['from_name'] as String?) ?? 'Sem nome';
                      final content = (msg['content'] as String?) ?? '';
                      return Text(
                        'Respondendo a $author: $content',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Cancelar',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    if (widget.editMessage != null) {
                      widget.onCancelEdit?.call();
                    } else {
                      widget.onCancelReply?.call();
                    }
                  },
                ),
              ],
            ),
          ),
        SizedBox(
          height: 70,
          child: Row(
            children: [
              Expanded(
                child: Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.enter):
                        _SendMessageIntent(),
                    SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                    ): _InsertNewLineIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _SendMessageIntent: CallbackAction<_SendMessageIntent>(
                        onInvoke: (intent) {
                          if (!isEnabled) {
                            return null;
                          }
                          _sendMessage();
                          return null;
                        },
                      ),
                      _InsertNewLineIntent:
                          CallbackAction<_InsertNewLineIntent>(
                        onInvoke: (intent) {
                          if (!isEnabled) {
                            return null;
                          }
                          _insertNewLine();
                          return null;
                        },
                      ),
                    },
                    child: CustomInput(
                      label: '',
                      hint: widget.roomId == null
                          ? 'Selecione uma conversa'
                          : (widget.editMessage != null
                              ? 'Edite sua mensagem'
                              : 'Digite sua mensagem'),
                      controller: widget.controller,
                      enabled: widget.roomId != null,
                      focusNode: _inputFocus,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      maxLines: 4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              SizedBox(
                height: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: IconButton(
                    tooltip: 'Anexar arquivo',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 56,
                      minHeight: 56,
                    ),
                    icon: const Icon(Icons.attach_file),
                    onPressed: isEnabled ? _sendAttachment : null,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              SizedBox(
                height: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 56,
                      minHeight: 56,
                    ),
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: isEnabled ? _sendMessage : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onFocusChanged() {
    if (!_inputFocus.hasFocus) {
      _setTyping(false);
    } else {
      _maybeStartTyping();
      if (widget.controller.text.trim().isNotEmpty) {
        widget.onTypingChanged?.call(true);
      }
    }
  }

  void _onTextChanged() {
    if (widget.roomId == null) {
      return;
    }
    if (widget.controller.text.trim().isEmpty) {
      _setTyping(false);
      return;
    }
    _maybeStartTyping();
    if (_isCurrentlyTyping) {
      widget.onTypingChanged?.call(true);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1200), () {
      _setTyping(false);
    });
  }

  void _maybeStartTyping() {
    if (!_isCurrentlyTyping) {
      _setTyping(true);
    }
  }

  void _setTyping(bool value) {
    if (_isCurrentlyTyping == value) {
      return;
    }
    _isCurrentlyTyping = value;
    widget.onTypingChanged?.call(value);
    if (value) {
      _typingPingTimer ??=
          Timer.periodic(const Duration(milliseconds: 800), (_) {
        if (!mounted) return;
        if (_isCurrentlyTyping && widget.roomId != null) {
          widget.onTypingChanged?.call(true);
        }
      });
    } else {
      _typingPingTimer?.cancel();
      _typingPingTimer = null;
    }
  }

  void _insertNewLine() {
    final controller = widget.controller;
    final selection = controller.selection;
    final text = controller.text;

    final start = selection.start;
    final end = selection.end;

    if (start < 0 || end < 0) {
      controller.value = TextEditingValue(
        text: '$text\n',
        selection: TextSelection.collapsed(offset: text.length + 1),
      );
      return;
    }

    final newText = text.replaceRange(start, end, '\n');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  Future<void> _sendMessage() async {
    final content = widget.controller.text.trim();
    if (content.isEmpty || widget.roomId == null) {
      return;
    }

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      if (widget.editMessage != null) {
        final messageId = widget.editMessage!['id'] as String?;
        if (messageId != null) {
          await Supabase.instance.client
              .from('messages')
              .update({
                'content': content,
                'edited_at': DateTime.now().toIso8601String(),
              })
              .eq('id', messageId)
              .eq('from_id', currentUser.id);
        }
        widget.controller.clear();
        _setTyping(false);
        widget.onCancelEdit?.call();
      } else {
        await Supabase.instance.client.from('messages').insert({
          'room_id': widget.roomId,
          'content': content,
          'from_id': currentUser.id,
          'from_name': currentUser.userMetadata?['full_name'] ??
              currentUser.email ??
              'Usuário',
          'parent_id': widget.replyToMessage != null
              ? widget.replyToMessage!['id']
              : null,
        });
        // Dispara Edge Function para enviar notificação push
        try {
          await Supabase.instance.client.functions.invoke(
            'send-notification', // nome da Edge Function no Supabase
            body: {
              'room_id': widget.roomId,
              'from_user_id': currentUser.id,
              'message_preview': content,
            },
          );
        } catch (_) {
          // Evita quebrar o fluxo de envio caso a função falhe
        }
        widget.controller.clear();
        _setTyping(false);
        if (widget.replyToMessage != null) {
          widget.onCancelReply?.call();
        }
      }
    } on PostgrestException catch (error) {
      String userMessage;
      final messageText = error.message;
      if (widget.editMessage != null &&
          (error.code == '42501' ||
              messageText.toLowerCase().contains('row-level security'))) {
        userMessage =
            'Você só pode editar mensagens por até 15 minutos após o envio.';
      } else {
        userMessage = 'Erro ao enviar mensagem: ${error.message}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage)),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro inesperado: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _sendAttachment() async {
    if (widget.roomId == null) {
      return;
    }

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final upload = await _attachmentService.pickAndUpload(widget.roomId!);
      if (upload == null) {
        // usuário cancelou
        return;
      }

      await Supabase.instance.client.from('messages').insert({
        'room_id': widget.roomId,
        'content': upload.url, // URL pública servida via CDN
        'from_id': currentUser.id,
        'from_name': currentUser.userMetadata?['full_name'] ??
            currentUser.email ??
            'Usuário',
      });
      // Dispara Edge Function para enviar notificação push de anexo
      try {
        await Supabase.instance.client.functions.invoke(
          'send-notification',
          body: {
            'room_id': widget.roomId,
            'from_user_id': currentUser.id,
            'message_preview': '📎 Novo anexo',
          },
        );
      } catch (_) {
        // Silencioso para não impactar UX de envio de anexo
      }
    } on AttachmentServiceException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on PostgrestException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar anexo: ${error.message}')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro inesperado ao enviar anexo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }
}

class _MobileChatScreen extends StatelessWidget {
  const _MobileChatScreen({
    required this.roomId,
    required this.textController,
    required this.inputFocus,
    this.roomData,
    this.title,
  });

  final String roomId;
  final String? title;
  final SidebarRoomData? roomData;
  final TextEditingController textController;
  final FocusNode inputFocus;

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeControllerProvider.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = colorScheme.brightness == Brightness.dark;

    return _MobileChatScaffold(
      roomId: roomId,
      title: title,
      roomData: roomData,
      textController: textController,
      inputFocus: inputFocus,
      themeController: themeController,
      isDarkMode: isDarkMode,
    );
  }
}

class _MobileAppBarTitle extends StatelessWidget {
  const _MobileAppBarTitle({
    required this.title,
    this.roomData,
    this.subtitle,
    this.onAvatarTap,
  });

  final String title;
  final SidebarRoomData? roomData;
  final Widget? subtitle;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = roomData;
    if (data == null) {
      if (subtitle == null) {
        return Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          DefaultTextStyle(
            style: Theme.of(context).textTheme.labelSmall ??
                TextStyle(color: scheme.onSurfaceVariant),
            child: subtitle!,
          ),
        ],
      );
    }

    Widget avatar;
    if (!data.isDirect) {
      final url = data.avatarUrl?.trim();
      if (url != null && url.isNotEmpty) {
        avatar = CircleAvatar(
          radius: 14,
          backgroundColor: scheme.secondaryContainer,
          child: ClipOval(
            child: Image.network(
              url,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.group_outlined,
                color: scheme.onSecondaryContainer,
                size: 18,
              ),
            ),
          ),
        );
      } else {
        avatar = CircleAvatar(
          radius: 14,
          backgroundColor: scheme.secondaryContainer,
          child: Icon(
            Icons.group_outlined,
            color: scheme.onSecondaryContainer,
            size: 18,
          ),
        );
      }
    } else {
      final url = data.avatarUrl?.trim();
      if (url != null && url.isNotEmpty) {
        avatar = CircleAvatar(
          radius: 14,
          backgroundColor: scheme.secondaryContainer,
          child: ClipOval(
            child: Image.network(
              url,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.person_outline,
                color: scheme.onSecondaryContainer,
                size: 18,
              ),
            ),
          ),
        );
      } else {
        avatar = CircleAvatar(
          radius: 14,
          backgroundColor: scheme.secondaryContainer,
          child: Icon(Icons.person_outline, color: scheme.onSecondaryContainer, size: 18),
        );
      }
    }

    final titleWidget = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final avatarWithHandler = (!data.isDirect && onAvatarTap != null)
        ? InkWell(
            onTap: onAvatarTap,
            customBorder: const CircleBorder(),
            child: avatar,
          )
        : avatar;

    if (subtitle == null) {
      return Row(
        children: [
          avatarWithHandler,
          const SizedBox(width: 8),
          Expanded(child: titleWidget),
        ],
      );
    }

    return Row(
      children: [
        avatarWithHandler,
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleWidget,
              const SizedBox(height: 2),
              DefaultTextStyle(
                style: Theme.of(context).textTheme.labelSmall ??
                    TextStyle(color: scheme.onSurfaceVariant),
                child: subtitle!,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileChatScaffold extends StatefulWidget {
  const _MobileChatScaffold({
    required this.roomId,
    required this.textController,
    required this.themeController,
    required this.isDarkMode,
    required this.inputFocus,
    this.roomData,
    this.title,
  });

  final String roomId;
  final String? title;
  final SidebarRoomData? roomData;
  final TextEditingController textController;
  final ThemeController themeController;
  final bool isDarkMode;
  final FocusNode inputFocus;

  @override
  State<_MobileChatScaffold> createState() => _MobileChatScaffoldState();
}

class _MobileChatScaffoldState extends State<_MobileChatScaffold> {
  RealtimeChannel? _channel;
  RealtimeChannel? _globalChannel;
  final Set<String> _onlineUserIds = <String>{};
  String? _peerUserId;
  bool _peerOnline = false;
  bool _peerTyping = false;
  Timer? _typingTimer;
  Map<String, dynamic>? _selectedMessage;
  Map<String, dynamic>? _replyTargetMessage;
  Map<String, dynamic>? _editingMessage;
  // Token usado para forçar o rebuild do ChatComponent e,
  // consequentemente, o recarregamento das mensagens/reações,
  // sem precisar sair e entrar novamente na conversa.
  int _chatReloadToken = 0;

  @override
  void initState() {
    super.initState();
    _subscribe(widget.roomId);
    _subscribeGlobal();
    _loadPeerUserId(widget.roomId);
  }

  @override
  void didUpdateWidget(covariant _MobileChatScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _subscribe(widget.roomId);
      _loadPeerUserId(widget.roomId);
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _channel?.unsubscribe();
    _globalChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribe(String roomId) {
    _typingTimer?.cancel();
    _channel?.unsubscribe();
    _peerOnline = false;
    _peerTyping = false;
    setState(() {});

    final channel = Supabase.instance.client.channel('room:$roomId', opts: const RealtimeChannelConfig(self: true));
    channel.onPresenceSync((_) {
      debugPrint('[presence][mobile][room:$roomId] sync');
      _updatePresenceState(channel);
    });
    channel.onPresenceJoin((_) {
      debugPrint('[presence][mobile][room:$roomId] join');
      _updatePresenceState(channel);
    });
    channel.onPresenceLeave((_) {
      debugPrint('[presence][mobile][room:$roomId] leave');
      _updatePresenceState(channel);
    });
    channel.onBroadcast(
      event: 'typing',
      callback: (dynamic payload, [ref]) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        final from = (payload is Map<String, dynamic> ? payload['user_id'] : null) as String? ?? '';
        final isTyping = (payload is Map<String, dynamic>) && payload['is_typing'] == true;
        if (from.isNotEmpty && from != currentUserId) {
          if (_peerTyping != isTyping) {
            setState(() {
              _peerTyping = isTyping;
            });
          }
          _typingTimer?.cancel();
          if (isTyping) {
            _typingTimer = Timer(const Duration(milliseconds: 1500), () {
              if (mounted) {
                if (_peerTyping) {
                  setState(() {
                    _peerTyping = false;
                  });
                }
              }
            });
          }
        }
      },
    );
    channel.subscribe((status, [ref]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        await channel.track({'user_id': currentUserId});
        debugPrint('[presence][mobile][room:$roomId] subscribed + tracked user_id=$currentUserId');
        _updatePresenceState(channel);
      }
    });
    _channel = channel;
  }

  void _updatePresenceState(RealtimeChannel channel) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final dynamic state = channel.presenceState();
    final presentIds = _extractUserIdsFromPresenceState(state);
    presentIds.remove(currentUserId);
    final newOnline = presentIds.isNotEmpty;
    debugPrint('[presence][mobile][room] state_ids=${presentIds.toList()} newOnline=$newOnline');
    if (newOnline != _peerOnline) {
      setState(() {
        _peerOnline = newOnline;
      });
    }
  }

  void _sendTyping(bool isTyping) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _channel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': currentUserId, 'is_typing': isTyping},
    );
  }

  void _subscribeGlobal() {
    _globalChannel?.unsubscribe();
    _onlineUserIds.clear();
    final channel = Supabase.instance.client
        .channel('online', opts: const RealtimeChannelConfig(self: true));
    void update() {
      final state = channel.presenceState();
      final ids = _extractUserIdsFromPresenceState(state);
      setState(() {
        _onlineUserIds
          ..clear()
          ..addAll(ids);
      });
      debugPrint('[presence][mobile][global] online_ids=${ids.toList()}');
    }
    channel.onPresenceSync((_) {
      debugPrint('[presence][mobile][global] sync');
      update();
    });
    channel.onPresenceJoin((_) {
      debugPrint('[presence][mobile][global] join');
      update();
    });
    channel.onPresenceLeave((_) {
      debugPrint('[presence][mobile][global] leave');
      update();
    });
    channel.subscribe((status, [ref]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null) {
          await channel.track({'user_id': currentUserId});
          debugPrint(
              '[presence][mobile][global] subscribed + tracked user_id=$currentUserId');
        } else {
          debugPrint(
              '[presence][mobile][global] subscribed but no authenticated user to track');
        }
        update();
      }
    });
    _globalChannel = channel;
  }

  Future<void> _toggleReactionMobile(
    String messageId,
    String roomId,
    String emoji,
  ) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;
    try {
      final existing = await Supabase.instance.client
          .from('message_reactions')
          .select('id')
          .eq('message_id', messageId)
          .eq('user_id', currentUserId)
          .eq('emoji', emoji)
          .maybeSingle();
      if (existing != null && existing.isNotEmpty) {
        final id = existing['id'] as String?;
        if (id != null) {
          await Supabase.instance.client
              .from('message_reactions')
              .delete()
              .eq('id', id);
        }
      } else {
        await Supabase.instance.client.from('message_reactions').insert({
          'message_id': messageId,
          'room_id': roomId,
          'user_id': currentUserId,
          'emoji': emoji,
        });
      }
      // Força o ChatComponent a ser reconstruído, garantindo que
      // as reações atualizadas sejam buscadas sem precisar sair da tela.
      if (mounted) {
        setState(() {
          _chatReloadToken++;
        });
      }
    } catch (e) {
      debugPrint('Erro ao alternar reação (mobile): $e');
    }
  }

  Future<void> _showEmojiPickerForMobile(
    BuildContext context,
    String messageId,
    String roomId,
  ) async {
    const emojis = [
      '😀','😂','😍','👍','👎','🙏','🔥','🎉','😮','😢','😡','🤔',
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: emojis.map((e) {
              return InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleReactionMobile(messageId, roomId, e);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 22)),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _loadPeerUserId(String roomId) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;
      final response = await Supabase.instance.client
          .from('room_members')
          .select('user_id')
          .eq('room_id', roomId)
          .neq('user_id', currentUserId);
      final list = (response as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
      final other = list.isNotEmpty ? (list.first['user_id'] as String?) : null;
      setState(() {
        _peerUserId = (other != null && other.isNotEmpty) ? other : null;
      });
    } catch (_) {
      setState(() {
        _peerUserId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final themeController = widget.themeController;
    Widget? subtitle;
    final isDirect = widget.roomData?.isDirect ?? false;
    if (_peerTyping) {
      // Em qualquer tipo de sala (direta ou grupo), exibimos o texto
      // "Digitando..." abaixo do título quando alguém estiver digitando.
      subtitle = const _TypingDots();
    } else if (isDirect) {
      final isOnline = _peerUserId != null && _onlineUserIds.contains(_peerUserId);
      final text = isOnline ? 'Online' : 'Offline';
      final dotColor = isOnline
          ? Colors.lightGreen
          : Theme.of(context).colorScheme.onSurfaceVariant;
      subtitle = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          Text(text),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _MobileAppBarTitle(
          title: widget.title ?? 'Conversa',
          roomData: widget.roomData,
          subtitle: subtitle,
          onAvatarTap: (widget.roomData != null &&
                  !(widget.roomData?.isDirect ?? true))
              ? () {
                  showGroupDetailsBottomSheet(
                    context,
                    roomId: widget.roomId,
                    roomName: widget.title ?? widget.roomData!.title,
                    avatarUrl: widget.roomData?.avatarUrl,
                  );
                }
              : null,
        ),
        actions: [
          if (_selectedMessage != null) ...[
            IconButton(
              tooltip: 'Responder',
              icon: const Icon(Icons.reply),
              onPressed: () {
                final m = _selectedMessage!;
                setState(() {
                  _replyTargetMessage = m;
                  _editingMessage = null;
                  _selectedMessage = null;
                });
              },
            ),
            if (_selectedMessage != null)
              Builder(
                builder: (context) {
                  final currentUserId =
                      Supabase.instance.client.auth.currentUser?.id;
                  final isMine =
                      (_selectedMessage!['from_id'] as String?) == currentUserId;

                  final createdAtRaw = _selectedMessage!['created_at'];
                  DateTime? createdAt;
                  if (createdAtRaw is String) {
                    createdAt = DateTime.tryParse(createdAtRaw);
                  } else if (createdAtRaw is DateTime) {
                    createdAt = createdAtRaw;
                  }
                  final createdAtUtc = createdAt?.toUtc();
                  final nowUtc = DateTime.now().toUtc();
                  final canEdit = isMine &&
                      createdAtUtc != null &&
                      nowUtc.difference(createdAtUtc).inMinutes < 15;

                  if (!canEdit) {
                    return const SizedBox.shrink();
                  }

                  return IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {
                      final m = _selectedMessage!;
                      setState(() {
                        _editingMessage = m;
                        _replyTargetMessage = null;
                        _selectedMessage = null;
                        widget.textController.text =
                            (m['content'] as String?) ?? '';
                        widget.textController.selection =
                            TextSelection.collapsed(
                          offset: widget.textController.text.length,
                        );
                      });
                    },
                  );
                },
              ),
            IconButton(
              tooltip: 'Apagar para todos',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final m = _selectedMessage!;
                final deleted = await _confirmAndDeleteMessageForAll(
                  context: context,
                  message: m,
                );
                if (deleted && mounted) {
                  setState(() {
                    _selectedMessage = null;
                  });
                }
              },
            ),
            IconButton(
              tooltip: 'Reagir',
              icon: const Icon(Icons.emoji_emotions_outlined),
              onPressed: () {
                final id = _selectedMessage!['id'] as String?;
                if (id != null) {
                  _showEmojiPickerForMobile(context, id, widget.roomId);
                }
                setState(() {
                  _selectedMessage = null;
                });
              },
            ),
            IconButton(
              tooltip: 'Fechar ações',
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectedMessage = null;
                });
              },
            ),
          ],
          IconButton(
            tooltip: isDarkMode ? 'Tema claro' : 'Tema escuro',
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: themeController.toggle,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ChatComponent(
              key: ValueKey('${widget.roomId}#$_chatReloadToken'),
              roomId: widget.roomId,
              selectedMessageId:
                  (_selectedMessage != null ? _selectedMessage!['id'] as String? : null),
              onReplyRequested: (message) {
                setState(() {
                  _editingMessage = null;
                  _replyTargetMessage = message;
                });
                widget.inputFocus.requestFocus();
              },
              onEditRequested: (message) {
                setState(() {
                  _replyTargetMessage = null;
                  _editingMessage = message;
                  widget.textController.text =
                      (message['content'] as String?) ?? '';
                  widget.textController.selection = TextSelection.collapsed(
                    offset: widget.textController.text.length,
                  );
                });
                widget.inputFocus.requestFocus();
              },
              onDeleteRequested: (message) {
                _confirmAndDeleteMessageForAll(
                  context: context,
                  message: message,
                );
              },
              onMessageTap: (message) {
                final current = _selectedMessage;
                if (current != null &&
                    (current['id'] as String?) ==
                        (message['id'] as String?)) {
                  setState(() {
                    _selectedMessage = null;
                  });
                }
              },
              onMessageLongPress: (message) {
                setState(() {
                  _selectedMessage = message;
                });
              },
              // Mostra o "bubble" de digitação para qualquer sala quando
              // recebemos evento de digitação de outro usuário.
              showTypingIndicator: _peerTyping,
            ),
            InputComponent(
              controller: widget.textController,
              roomId: widget.roomId,
              replyToMessage: _replyTargetMessage,
              editMessage: _editingMessage,
              focusNode: widget.inputFocus,
              onCancelReply: () {
                setState(() {
                  _replyTargetMessage = null;
                });
              },
              onCancelEdit: () {
                setState(() {
                  _editingMessage = null;
                  widget.textController.clear();
                });
              },
              onTypingChanged: _sendTyping,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchGroupsScreen extends StatefulWidget {
  const _SearchGroupsScreen({required this.onEnterRoom});

  final void Function(String roomId, String title) onEnterRoom;

  @override
  State<_SearchGroupsScreen> createState() => _SearchGroupsScreenState();
}

class _SearchGroupsScreenState extends State<_SearchGroupsScreen> {
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchSearchableGroups() async {
    final response = await Supabase.instance.client
        .from('rooms')
        .select('id, name, type, updated_at, is_searchable')
        .eq('type', 'group')
        .eq('is_searchable', true)
        .order('updated_at', ascending: false);
    return (response as List).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> _enterGroup(Map<String, dynamic> room) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faça login para entrar em um grupo.')),
      );
      return;
    }
    final roomId = room['id'] as String?;
    final name = (room['name'] as String?)?.trim() ?? 'Grupo';
    if (roomId == null || roomId.isEmpty) return;

    try {
      // Verifica se já é membro
      final existing = await Supabase.instance.client
          .from('room_members')
          .select('room_id')
          .eq('room_id', roomId)
          .eq('user_id', currentUser.id)
          .maybeSingle();
      if (existing == null) {
        await Supabase.instance.client.from('room_members').insert({
          'room_id': roomId,
          'user_id': currentUser.id,
        });
      }
      widget.onEnterRoom(roomId, name);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao entrar no grupo: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro inesperado: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesquisar grupos'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _queryController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nome do grupo',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchSearchableGroups(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Erro ao carregar grupos: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final allRooms = (snapshot.data ?? [])
                    .whereType<Map<String, dynamic>>()
                    .toList();
                final q = _queryController.text.trim().toLowerCase();
                final rooms = q.isEmpty
                    ? allRooms
                    : allRooms.where((r) {
                        final name = (r['name'] as String?)?.toLowerCase() ?? '';
                        return name.contains(q);
                      }).toList();

                if (rooms.isEmpty) {
                  return const Center(
                    child: Text('Nenhum grupo encontrado.'),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      final title =
                          (room['name'] as String?)?.trim() ?? 'Grupo';
                      return Card(
                        color: scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.secondaryContainer,
                            child: Icon(
                              Icons.group_outlined,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                          title: Text(title),
                          subtitle: const Text('Grupo público pesquisável'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _enterGroup(room),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Exibe um modal de confirmação e marca a mensagem como apagada para todos.
///
/// Retorna `true` se a mensagem foi efetivamente apagada.
Future<bool> _confirmAndDeleteMessageForAll({
  required BuildContext context,
  required Map<String, dynamic> message,
}) async {
  final messageId = message['id'] as String?;
  if (messageId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Não foi possível identificar a mensagem.'),
      ),
    );
    return false;
  }

  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Usuário não autenticado.'),
      ),
    );
    return false;
  }

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Apagar mensagem'),
        content: const Text(
          'Deseja apagar esta mensagem para todos? Essa ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return false;
  }

  try {
    await Supabase.instance.client
        .from('messages')
        .update({'is_deleted': true})
        .eq('id', messageId)
        .eq('from_id', currentUser.id);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mensagem apagada para todos.'),
      ),
    );
    return true;
  } on PostgrestException catch (error) {
    var userMessage = 'Erro ao apagar mensagem: ${error.message}';
    final messageText = error.message.toLowerCase();
    if (error.code == '42501' ||
        messageText.contains('row-level security')) {
      userMessage = 'Você não tem permissão para apagar esta mensagem.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userMessage)),
    );
  } catch (error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Erro inesperado ao apagar mensagem: $error',
        ),
      ),
    );
  }
  return false;
}
