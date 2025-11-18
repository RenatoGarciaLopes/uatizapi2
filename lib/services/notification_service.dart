import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço responsável por configurar e gerenciar notificações push (FCM).
class NotificationService {
  NotificationService._internal();

  /// Instância singleton.
  static final NotificationService instance = NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Inicializa o FCM:
  /// - pede permissão (iOS / Web);
  /// - configura apresentação em foreground (iOS/macOS/Web);
  /// - obtém o token atual;
  /// - começa a escutar mensagens.
  Future<void> init() async {
    // Permissões específicas de iOS/macOS/Web
    await _requestPermission();

    // Exibir notificações também em foreground (Apple / Web).
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Obtém o token do dispositivo.
    final token = await getToken();
    debugPrint('FCM token atual: $token');

    // TODO: Opcional – sincronizar token com Supabase após login:
    // final userId = Supabase.instance.client.auth.currentUser?.id;
    // if (userId != null) {
    //   await syncTokenWithSupabase(userId: userId);
    // }

    _listenToMessages();
  }

  /// Pede permissão de notificações (principalmente necessário em iOS/macOS/Web).
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      
    );

    debugPrint('Permissão de notificação: ${settings.authorizationStatus}');
  }

  /// Retorna o token FCM atual.
  ///
  /// Em Web é possível que você precise configurar a VAPID key na chamada
  /// (substitua pelo valor público gerado no Firebase console).
  Future<String?> getToken() async {
    if (kIsWeb) {
      // Chave pública WebPush (VAPID) gerada na aba Cloud Messaging do Firebase.
      const webPushPublicKey =
          'BEEOQKQXsuGwqtKL1e-p2OGcCXKLV-cfNpRkiKnMkK4WMSZALLvlI_0lkhyAO09LJcp-h2td7jxxN_UzSvjY8Ow';
      return _messaging.getToken(vapidKey: webPushPublicKey);
    }
    return _messaging.getToken();
  }

  /// Escuta mensagens recebidas enquanto o app está aberto.
  void _listenToMessages() {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Mensagem FCM em foreground: ${message.messageId}');

      final notification = message.notification;
      if (notification != null) {
        debugPrint(
          'Título: ${notification.title} | Corpo: ${notification.body}',
        );
      }

      // Aqui você pode:
      // - mostrar um diálogo/snackbar;
      // - acionar uma notificação local;
      // - atualizar o estado da tela de conversas.
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Usuário abriu o app a partir de uma notificação FCM.');

      // TODO: Se quiser navegar para uma conversa específica, use os dados:
      // final roomId = message.data['room_id'];
      // e navegue via Navigator ou rotas nomeadas.
    });
  }

  /// Exemplo de sincronização do token com Supabase.
  ///
  /// Crie uma tabela, por exemplo `fcm_tokens`, com colunas:
  /// - user_id (uuid, referência para auth.users)
  /// - token (text, unique)
  /// - platform (text)
  /// - updated_at (timestamp)
  Future<void> syncTokenWithSupabase({required String userId}) async {
    final token = await getToken();
    if (token == null) return;

    final client = Supabase.instance.client;

    await client.from('fcm_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': defaultTargetPlatform.name.toLowerCase(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}


