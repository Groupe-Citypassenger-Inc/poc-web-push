import './style.css';

let alerts = [] as string[];

async function getAndDisplayNotifications(serviceWorkerRegistration: ServiceWorkerRegistration) {
  const notifications = await serviceWorkerRegistration.getNotifications();
  console.log('Notifications', notifications);
  const noNotificationEl = document.getElementById('no-notification');
  const notificationsEl = document.getElementById('notifications');

  if (!notificationsEl || !noNotificationEl) return;

  noNotificationEl.style.display = notifications.length === 0 ? 'block' : 'none';
  notificationsEl.innerHTML = '';

  notifications.forEach((notification) => {
    const li = document.createElement('li');
    li.textContent = `${notification.data.date.toLocaleString()} - ${notification.data.log}`;
    notificationsEl.appendChild(li);
  });
}

function displayAlerts(subscription: PushSubscription) {
  const noAlertEl = document.getElementById('no-alert');
  const alertsEl = document.getElementById('alerts');

  if (!alertsEl || !noAlertEl) return;

  noAlertEl.style.display = alerts.length === 0 ? 'block' : 'none';
  alertsEl.innerHTML = '';

  alerts.forEach((alert) => {
    const button = document.createElement('button');
    button.innerText = 'Supprimer';
    button.onclick = () => deleteAlert(subscription, alert);
    const li = document.createElement('li');
    li.textContent = alert;
    li.appendChild(button);
    alertsEl.appendChild(li);
  })
}

async function deleteAlert(subscription: PushSubscription, alert: string) {
  fetch('/wps/delete-subscription', {
    method: 'DELETE',
    body: new URLSearchParams({
      groupName: 'dev-nathan',
      regex: alert,
      subscription: JSON.stringify(subscription.toJSON()),
    })
  }).then(() => {
    alerts = alerts.filter((a) => a !== alert);
    displayAlerts(subscription);
  });
}

function fetchAndDisplayAlerts(subscription: PushSubscription) {
  fetch('/wps/get-subscriptions', {
    method: 'POST',
    body: new URLSearchParams({
      groupName: 'dev-nathan',
      subscription: JSON.stringify(subscription.toJSON()),
    }),
  })
  .then(response => response.json())
  .then((newAlerts) => {
    alerts = newAlerts;
    displayAlerts(subscription)
  });
}

function handleCreateAlertForm(subscription: PushSubscription) {
  const form = document.getElementById('alert-form');
  if (!form ) return;

  form.onsubmit = (event) => {
    event.preventDefault();
    const form = event.target as HTMLFormElement;
    const newAlert = form.regex.value;
    fetch('/wps/subscribe', {
      method: 'POST',
      body: new URLSearchParams({
        groupName: 'dev-nathan',
        regex: newAlert,
        subscription: JSON.stringify(subscription.toJSON()),
      })
    }).then(() => {
      alerts.push(newAlert);
      displayAlerts(subscription);
    });
  }
}

function handleSimulateLogForm() {
  const form = document.getElementById('log-form');
  if (!form ) return;

  form.onsubmit = (event) => {
    event.preventDefault();
    const form = event.target as HTMLFormElement;
    const newLog = form.log.value;
    fetch('/wps/simulate-log', {
      method: 'POST',
      body: new URLSearchParams({
        groupName: 'dev-nathan',
        log: newLog,
      })
    });
  }
}

(async () => {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    console.error('No service worker or push manager support');
    return;
  }

  const permission = await Notification.requestPermission();

  if (permission !== 'granted') {
    console.error('No permission for notifications');
    return;
  }

  const registerServiceWorker = async (): Promise<ServiceWorkerRegistration> => {
    console.log('Registering service worker');
    await navigator.serviceWorker.register('/service-worker.js');
    return await navigator.serviceWorker.ready;
  }

  const serviceWorkerRegistration = await navigator.serviceWorker.getRegistration()
    ?? await registerServiceWorker();

  getAndDisplayNotifications(serviceWorkerRegistration);

  serviceWorkerRegistration.addEventListener('push', () => {
    console.log('Push event received');
    getAndDisplayNotifications(serviceWorkerRegistration);
  });

  const createSubscription = (): Promise<PushSubscription> => {
    console.log('Creating subscription');
    return serviceWorkerRegistration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: __APP_PUSH_PUBLIC_KEY__,
    });
  }

  const subscription = await serviceWorkerRegistration.pushManager.getSubscription()
    ?? await createSubscription();


  fetchAndDisplayAlerts(subscription);
  handleCreateAlertForm(subscription);
  handleSimulateLogForm();
})();
