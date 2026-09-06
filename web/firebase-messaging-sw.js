/* Firebase Cloud Messaging - Service Worker para web */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB2FakN7gtSzWekqRbDmKR_1WQCkBowXDs',
  authDomain: 'territorio-sur-8b72c.firebaseapp.com',
  projectId: 'territorio-sur-8b72c',
  storageBucket: 'territorio-sur-8b72c.firebasestorage.app',
  messagingSenderId: '288799954885',
  appId: '1:288799954885:web:32ae6dfbc7d871b30bddac',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[FCM] Mensaje en background:', payload);
  const title = payload.notification?.title ?? 'Araucaria Sur';
  const options = {
    body: payload.notification?.body ?? '',
    data: payload.data ?? {},
  };
  self.registration.showNotification(title, options);
});
