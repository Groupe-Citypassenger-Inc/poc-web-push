self.addEventListener('push', function (event) {
  if (!event.data) return;
  const notification = event.data.json();
  self.registration.showNotification(notification.title, {
    body: notification.body,
    data: {
      date: new Date(),
      ...notification.data,
    },
    icon: './android-chrome-192x192.png',
  });
});

self.addEventListener('notificationclick', function (event) {
  const promiseChain = clients
    .matchAll({ type: 'window', includeUncontrolled: true, })
    .then((windowClients) => {
      const openClient = windowClients.find((client) => {
        const url = new URL(client.url);
        return url.origin === self.location.origin;
      });

      if (openClient) return openClient.focus();

      const alertUrl = new URL(self.location.origin);
      return clients.openWindow(alertUrl);
    });

  event.waitUntil(promiseChain);
});
