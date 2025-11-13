import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zapizapi/services/attachment_service.dart';
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
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  String? _selectedRoomId;
  SidebarRoomData? _selectedRoomData;
  late final AnimationController _introController;
  late final Animation<Offset> _slideIn;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                        padding: EdgeInsets.only(
                          left: sidebarWidth + 32,
                          right: 24,
                          top: 24,
                          bottom: 24,
                        ),
                        child: Column(
                          children: [
                            ChatComponent(roomId: _selectedRoomId),
                            InputComponent(
                              controller: _textController,
                              roomId: _selectedRoomId,
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
                        right: 0,
                        bottom: 24,
                      ),
                      child: OpenConversationsSidebar(
                        selectedRoomId: _selectedRoomId,
                        onCreateNewConversation: _showNewConversationDialog,
                        onRoomSelected: (room) {
                          setState(() {
                            _selectedRoomId = room.id;
                            _selectedRoomData = room;
                          });
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

    return Row(
      children: [
        _buildHeaderAvatar(selectedRoom, headerForeground),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            selectedRoom.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: headerForeground,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
}

/// Componente de chat
class ChatComponent extends StatefulWidget {
  /// Construtor da classe [ChatComponent]
  const ChatComponent({required this.roomId, super.key});

  /// Identificador da sala selecionada.
  final String? roomId;

  @override
  State<ChatComponent> createState() => _ChatComponentState();
}

class _ChatComponentState extends State<ChatComponent> {
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;

  @override
  void didUpdateWidget(covariant ChatComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomId != oldWidget.roomId) {
      _lastMessageCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
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

  @override
  Widget build(BuildContext context) {
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
        stream: Supabase.instance.client
            .from('messages')
            .stream(primaryKey: ['id'])
            .eq('room_id', roomId)
            .order('created_at', ascending: true),
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

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final isMine = message['from_id'] == currentUserId;
              final content = message['content'] as String? ?? '';
              final author = message['from_name'] as String? ?? 'Sem nome';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Align(
                  alignment: isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isMine
                            ? scheme.primaryContainer
                            : scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMine
                              ? Colors.transparent
                              : scheme.outlineVariant,
                        ),
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
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            if (_isImageUrl(content))
                              _MessageImage(
                                url: content,
                                onTap: () => _openImageViewer(context, content),
                              )
                            else if (_isUrl(content))
                              InkWell(
                                onTap: () => _openUrl(content),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
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
                                                  TextDecoration.underline,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Text(
                                content,
                                style: Theme.of(context).textTheme.bodyMedium,
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
      ),
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
    super.key,
  });

  /// Controlador de texto
  final TextEditingController controller;

  /// Sala selecionada para envio
  final String? roomId;

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
  final AttachmentService _attachmentService = AttachmentService();

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode();
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.roomId != null && !_isSending;

    return SizedBox(
      height: 70,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(LogicalKeyboardKey.enter):
                    _SendMessageIntent(),
                const SingleActivator(
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
                  _InsertNewLineIntent: CallbackAction<_InsertNewLineIntent>(
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
                      : 'Digite sua mensagem',
                  controller: widget.controller,
                  enabled: widget.roomId != null,
                  focusNode: _inputFocus,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  minLines: 1,
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
    );
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
      await Supabase.instance.client.from('messages').insert({
        'room_id': widget.roomId,
        'content': content,
        'from_id': currentUser.id,
        'from_name':
            currentUser.userMetadata?['full_name'] ??
            currentUser.email ??
            'Usuário',
      });
      widget.controller.clear();
    } on PostgrestException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar mensagem: ${error.message}')),
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
