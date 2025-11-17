import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zapizapi/services/avatar_service.dart';
import 'package:zapizapi/ui/features/home/widgets/sidebar_skeleton.dart';
import 'package:zapizapi/ui/theme/brand_colors.dart';

/// Modelo de dados utilizado para renderizar a sidebar.
class SidebarRoomData {
  SidebarRoomData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isDirect,
    this.avatarUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool isDirect;
  final String? avatarUrl;
}

/// Sidebar que exibe as conversas abertas através da tabela `rooms`.
class OpenConversationsSidebar extends StatefulWidget {
  /// Construtor padrão
  const OpenConversationsSidebar({
    required this.onRoomSelected,
    this.selectedRoomId,
    this.onCreateNewConversation,
    this.width,
    super.key,
  });

  /// Callback acionado ao selecionar uma sala.
  final ValueChanged<SidebarRoomData> onRoomSelected;

  /// Sala atualmente selecionada.
  final String? selectedRoomId;

  /// Callback para acionar criação de nova conversa.
  final VoidCallback? onCreateNewConversation;
  /// Largura desejada. Se nulo, usa 280 (padrão desktop).
  final double? width;

  @override
  State<OpenConversationsSidebar> createState() =>
      _OpenConversationsSidebarState();
}

class _OpenConversationsSidebarState extends State<OpenConversationsSidebar> {
  List<SidebarRoomData> _cachedRooms = [];
  bool _isFetchingRooms = false;
  Set<String> _knownRoomIds = {};
  String? _lastNotifiedRoomId;
  String? _currentUserAvatarUrl;
  bool _isUploadingAvatar = false;
  Stream<List<Map<String, dynamic>>>? _membershipsStream;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserAvatar();
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null) {
      _membershipsStream = Supabase.instance.client
          .from('room_members')
          .stream(primaryKey: ['room_id', 'user_id'])
          .eq('user_id', currentUserId);
    }
  }

  Future<void> _showAvatarModal() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: scheme.surfaceContainerHigh,
                foregroundColor: scheme.onSurfaceVariant,
                child: _currentUserAvatarUrl != null &&
                        _currentUserAvatarUrl!.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          _currentUserAvatarUrl!,
                          width: 112,
                          height: 112,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.person_outline,
                            color: scheme.onSurfaceVariant,
                            size: 56,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.person_outline,
                        color: scheme.onSurfaceVariant,
                        size: 56,
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUploadingAvatar
                          ? null
                          : () {
                              // Fecha o modal e depois remove o avatar
                              Navigator.of(context).pop();
                              _removeAvatar();
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remover foto'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isUploadingAvatar ? null : _pickNewAvatar,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Escolher foto'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadCurrentUserAvatar() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;
    try {
      final raw = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', currentUserId)
          .maybeSingle();
      if (!mounted) return;
      final map =
          raw == null ? null : Map<String, dynamic>.from(raw as Map<dynamic, dynamic>);
      setState(() {
        _currentUserAvatarUrl =
            (map?['avatar_url'] as String?)?.trim();
      });
    } catch (_) {
      // Silencioso: avatar é opcional
    }
  }

  Future<void> _pickNewAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _isUploadingAvatar = true);
    try {
      final avatarService = AvatarService();
      final upload =
          await avatarService.pickAndUploadAvatar(userId: user.id);
      if (upload == null) {
        setState(() => _isUploadingAvatar = false);
        return;
      }
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': upload.url})
          .eq('id', user.id);
      if (!mounted) return;
      setState(() {
        _currentUserAvatarUrl = upload.url;
        _isUploadingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil atualizada.')),
      );
    } on AvatarServiceException catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar perfil: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro inesperado: $e')),
      );
    }
  }

  Future<void> _removeAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _isUploadingAvatar = true);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': null})
          .eq('id', user.id);
      if (!mounted) return;
      setState(() {
        _currentUserAvatarUrl = null;
        _isUploadingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil removida.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar perfil: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro inesperado: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final currentUser = Supabase.instance.client.auth.currentUser;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final displayName = (currentUser?.userMetadata?['full_name'] as String?)
        ?.trim();
    final fallbackName = (currentUser?.email ?? '').split('@').first;
    final userName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (fallbackName.isNotEmpty ? fallbackName : 'Usuário');

    if (currentUserId == null) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        elevation: 12,
        color: scheme.surface,
        shadowColor: Colors.black.withOpacity(0.12),
        child: SizedBox(
          width: widget.width ?? 280,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _showAvatarModal,
                        customBorder: const CircleBorder(),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: scheme.primaryContainer,
                              foregroundColor: scheme.onPrimaryContainer,
                              child: _currentUserAvatarUrl != null &&
                                      _currentUserAvatarUrl!.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        _currentUserAvatarUrl!,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.person_outline,
                                          color: scheme.onPrimaryContainer,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.person_outline,
                                      color: scheme.onPrimaryContainer,
                                    ),
                            ),
                            if (_isUploadingAvatar)
                              const SizedBox(
                                width: 44,
                                height: 44,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _showAvatarModal,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName,
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Alterar foto',
                                  style:
                                      theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SvgPicture.asset(
                        'assets/icons/ic-menu-dots-circle-broken.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          scheme.onSurfaceVariant,
                          BlendMode.srcIn,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Conversas',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (widget.onCreateNewConversation != null)
                        Tooltip(
                          message: 'Nova conversa',
                          child: Material(
                            color: BrandColors.accentGreen,
                            shape: const CircleBorder(),
                            elevation: 2,
                            shadowColor: BrandColors.accentGreen.withOpacity(
                              0.25,
                            ),
                            child: InkWell(
                              onTap: widget.onCreateNewConversation,
                              customBorder: const CircleBorder(),
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: Center(
                                  child: SvgPicture.asset(
                                    'assets/icons/ic_pen-new-square-broken.svg',
                                    width: 20,
                                    height: 20,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _membershipsStream,
                    builder: (context, snapshot) {
                      if (_membershipsStream == null) {
                        return const SidebarSkeleton();
                      }
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          _cachedRooms.isEmpty) {
                        return const SidebarSkeleton();
                      }

                      if (snapshot.hasError) {
                        return _ErrorMessage(
                          message: 'Erro ao carregar conversas',
                          details: '${snapshot.error}',
                        );
                      }

                      final memberships = snapshot.data;

                      if (memberships == null || memberships.isEmpty) {
                        _scheduleRoomRefresh([], currentUserId);
                        return const _EmptyState(
                          message: 'Nenhuma conversa encontrada',
                        );
                      }

                      _scheduleRoomRefresh(memberships, currentUserId);

                      if (_isFetchingRooms && _cachedRooms.isEmpty) {
                        return const SidebarSkeleton();
                      }

                      if (_cachedRooms.isEmpty) {
                        return const _EmptyState(
                          message: 'Nenhuma conversa encontrada',
                        );
                      }

                      return Stack(
                        children: [
                          ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: _cachedRooms.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final room = _cachedRooms[index];
                              final isSelected =
                                  room.id == widget.selectedRoomId;

                              return AnimatedScale(
                                duration: const Duration(milliseconds: 200),
                                scale: isSelected ? 1.02 : 1,
                                child: Card(
                                  color: isSelected
                                      ? (scheme.brightness == Brightness.light
                                            ? scheme.primaryContainer
                                                  .withOpacity(0.3)
                                            : scheme.surfaceContainerLowest)
                                      : scheme.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: _SidebarAvatar(
                                      room: room,
                                      isSelected: isSelected,
                                      scheme: scheme,
                                    ),
                                    title: Text(
                                      room.title,
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color:
                                                isSelected &&
                                                    scheme.brightness ==
                                                        Brightness.light
                                                ? scheme.onPrimaryContainer
                                                : null,
                                          ),
                                    ),
                                    subtitle: Text(
                                      room.subtitle,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color:
                                                isSelected &&
                                                    scheme.brightness ==
                                                        Brightness.light
                                                ? scheme.onPrimaryContainer
                                                      .withOpacity(0.9)
                                                : null,
                                          ),
                                    ),
                                    onTap: () {
                                      widget.onRoomSelected(room);
                                      _lastNotifiedRoomId = room.id;
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_isFetchingRooms)
                            const Positioned(
                              left: 12,
                              right: 12,
                              top: 0,
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<List<SidebarRoomData>> _loadRooms(
    List<Map<String, dynamic>> memberships,
    String currentUserId,
  ) async {
    if (memberships.isEmpty) {
      return [];
    }

    final roomIds = memberships
        .map((membership) => membership['room_id'])
        .whereType<String>()
        .toSet()
        .toList();

    if (roomIds.isEmpty) {
      return [];
    }

    final idsFilter = '(${roomIds.map((id) => '"$id"').join(',')})';

    final rawRoomsResponse = await Supabase.instance.client
        .from('rooms')
        .select(
          'id, name, type, updated_at, created_at',
        )
        .filter('id', 'in', idsFilter);

    final rawMembersResponse = await Supabase.instance.client
        .from('room_members')
        .select(
          'room_id, user_id, profiles ( full_name, email, avatar_url )',
        )
        .filter('room_id', 'in', idsFilter);

    final roomsResponse = (rawRoomsResponse as List)
        .whereType<Map<String, dynamic>>()
        .toList();
    final membersResponse = (rawMembersResponse as List)
        .whereType<Map<String, dynamic>>()
        .toList();

    final rooms = <SidebarRoomData>[];

    for (final room in roomsResponse) {
      final roomId = room['id'] as String?;
      if (roomId == null) {
        continue;
      }

      final type = room['type'] as String? ?? 'direct';
      final name = (room['name'] as String?)?.trim();

      var title = name ?? 'Conversa';
      var subtitle = 'ID: ${roomId.substring(0, 8)}';
      String? avatarUrl;

      final relatedMembers = membersResponse.where(
        (member) => member['room_id'] == roomId,
      );

      if (type == 'direct') {
        Map<String, dynamic>? otherMember;
        for (final member in relatedMembers) {
          if (member['user_id'] != currentUserId) {
            otherMember = member;
            break;
          }
        }

        final profile = otherMember?['profiles'] as Map<String, dynamic>?;
        final fullName = (profile?['full_name'] as String?)?.trim();
        final email = (profile?['email'] as String?)?.trim();
        avatarUrl = (profile?['avatar_url'] as String?)?.trim();

        title = fullName?.isNotEmpty ?? false
            ? fullName!
            : (email?.isNotEmpty ?? false ? email! : 'Conversa direta');
        subtitle = 'ID: ${roomId.substring(0, 8)}';
      } else {
        title = name?.isNotEmpty ?? false ? name! : 'Grupo';
        subtitle = '${relatedMembers.length} participante(s)';
      }

      rooms.add(
        SidebarRoomData(
          id: roomId,
          title: title,
          subtitle: subtitle,
          isDirect: type == 'direct',
          avatarUrl: type == 'direct' ? avatarUrl : null,
        ),
      );
    }

    rooms.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    return rooms;
  }

  void _scheduleRoomRefresh(
    List<Map<String, dynamic>> memberships,
    String currentUserId,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final roomIds = memberships
          .map((membership) => membership['room_id'])
          .whereType<String>()
          .toSet();

      final hasSameRooms =
          roomIds.length == _knownRoomIds.length &&
          roomIds.containsAll(_knownRoomIds);

      if (hasSameRooms && _cachedRooms.isNotEmpty) {
        if (_isFetchingRooms) {
          setState(() {
            _isFetchingRooms = false;
          });
        }
        return;
      }

      if (roomIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _knownRoomIds = roomIds;
          _cachedRooms = [];
          _isFetchingRooms = false;
        });
        return;
      }

      setState(() {
        _isFetchingRooms = true;
        _knownRoomIds = roomIds;
      });

      final rooms = await _loadRooms(memberships, currentUserId);
      if (!mounted) return;

      setState(() {
        _cachedRooms = rooms;
        _isFetchingRooms = false;
      });
      _notifySelectedRoomIfNeeded(rooms);
    });
  }

  void _notifySelectedRoomIfNeeded(List<SidebarRoomData> rooms) {
    final selectedRoomId = widget.selectedRoomId;
    if (selectedRoomId == null || selectedRoomId == _lastNotifiedRoomId) {
      return;
    }

    SidebarRoomData? selectedRoom;
    for (final room in rooms) {
      if (room.id == selectedRoomId) {
        selectedRoom = room;
        break;
      }
    }

    if (selectedRoom == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onRoomSelected(selectedRoom!);
      _lastNotifiedRoomId = selectedRoomId;
    });
  }
}

class _SidebarAvatar extends StatelessWidget {
  const _SidebarAvatar({
    required this.room,
    required this.isSelected,
    required this.scheme,
  });

  final SidebarRoomData room;
  final bool isSelected;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isSelected
        ? scheme.primary
        : scheme.secondaryContainer;
    final foregroundColor = isSelected
        ? scheme.onPrimary
        : scheme.onSecondaryContainer;

    if (!room.isDirect) {
      return CircleAvatar(
        backgroundColor: backgroundColor,
        child: Icon(
          Icons.group_outlined,
          color: foregroundColor,
        ),
      );
    }

    final avatarUrl = room.avatarUrl?.trim();

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        child: ClipOval(
          child: Image.network(
            avatarUrl,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.person_outline,
              color: foregroundColor,
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      child: Icon(
        Icons.person_outline,
        color: foregroundColor,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({
    required this.message,
    required this.details,
  });

  final String message;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              details,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
