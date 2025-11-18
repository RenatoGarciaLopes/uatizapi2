/* eslint-disable no-undef */
// Service worker para receber notificações FCM em background no Web.
// ATENÇÃO: substitua os valores de configuração abaixo pelos dados do seu
// projeto Firebase (os mesmos que aparecem no `firebase_options.dart`).

importScripts('https://www.gstatic.com/firebasejs/9.6.10/firebase-app-compat.js');
importScripts(
  'https://www.gstatic.com/firebasejs/9.6.10/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyAPWOecKFnnY9QIjite7n0A45hkD2nz7eg',
  authDomain: 'uatizapi2-ded6f.firebaseapp.com',
  projectId: 'uatizapi2-ded6f',
  storageBucket: 'uatizapi2-ded6f.firebasestorage.app',
  messagingSenderId: '1094783952092',
  appId: '1:1094783952092:web:dfba8c8354797b1d208019',
});

const messaging = firebase.messaging();

// Chamado quando uma mensagem é recebida com o app fechado/em background.
messaging.onBackgroundMessage((payload) => {
  console.log(
    '[firebase-messaging-sw.js] Mensagem recebida em background',
    payload,
  );

  const notificationTitle =
    (payload.notification && payload.notification.title) || 'Nova mensagem';

  const notificationOptions = {
    body:
      (payload.notification && payload.notification.body) ||
      'Você recebeu uma nova mensagem.',
    icon: '/icons/Icon-192.png',
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});


