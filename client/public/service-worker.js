const appUrl = new URL('/notification', self.location.origin).href;

async function getFirstCurrentClient() {
  const matchingClients = await clients.matchAll({
    type: 'window', includeUncontrolled: true,
  });
  const firstClient = matchingClients.find((client) => client.url === appUrl);
  return firstClient;
}

self.addEventListener('push', async (event) => {
  if (!event.data) return;
  const notification = event.data.json();
  notification.data = {
    date: new Date(),
    ...notification.data,
  };
  notification.icon = './android-chrome-192x192.png';
  self.registration.showNotification(notification.title, notification);
  const client = await getFirstCurrentClient();
  if (client) client.postMessage(notification);
});

self.addEventListener('notificationclick', function (event) {
  const promiseChain = getFirstCurrentClient().then((client) => {
    if (client) return client.focus();
    return clients.openWindow(appUrl);
  });

  event.waitUntil(promiseChain);
});
