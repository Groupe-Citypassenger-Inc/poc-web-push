import './style.css';

interface Alert {
  regex: string;
  is_notified: 1 | 0,
}

let alerts = [] as Alert[];
let notifications = [] as Notification[];

async function displayNotifications() {
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

async function unsubscribe(subscription: PushSubscription, alert: Alert) {
  fetch('/wps/delete-subscription', {
    method: 'DELETE',
    body: new URLSearchParams({
      groupName: 'dev-nathan',
      regex: alert.regex,
      subscription: JSON.stringify(subscription.toJSON()),
    })
  }).then(() => {
    alert.is_notified = 0;
    displayAlerts(subscription);
  });
}

function subscribe(subscription: PushSubscription, alert: Alert) {
  fetch('/wps/subscribe', {
    method: 'POST',
    body: new URLSearchParams({
      groupName: 'dev-nathan',
      regex: alert.regex,
      subscription: JSON.stringify(subscription.toJSON()),
    })
  }).then(() => {
    alert.is_notified = 1;
    displayAlerts(subscription);
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
    button.innerText = alert.is_notified ? 'Ne plus me notifier sur ce navigateur' : 'Me notifier sur ce navigateur';
    button.onclick = () => (alert.is_notified ? unsubscribe : subscribe)(subscription, alert);
    const li = document.createElement('li');
    const notifyText = alert.is_notified ? 'Notifié sur ce navigateur' : 'Non notifié sur ce navigateur';
    li.textContent = `"${alert.regex}" (${notifyText})`;
    li.appendChild(button);
    alertsEl.appendChild(li);
  })
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
  if (!form) return;
  form.onsubmit = (event) => {
    event.preventDefault();
    const form = event.target as HTMLFormElement;
    const regex = form.regex.value as string;
    const newAlert: Alert = { regex, is_notified: 0 };
    alerts.push(newAlert);
    subscribe(subscription, newAlert);
  }
}

function handleSimulateLogForm() {
  const form = document.getElementById('log-form');
  if (!form) return;

  form.onsubmit = async (event) => {
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

async function initialize(askPermissionBtn: HTMLElement) {
  const app = document.getElementById('app');
  if (!app) return;
  app.style.display = 'block';
  askPermissionBtn.style.display = 'none';

  const registerServiceWorker = async (): Promise<ServiceWorkerRegistration> => {
    console.log('Registering service worker');
    await navigator.serviceWorker.register('/service-worker.js');
    return await navigator.serviceWorker.ready;
  }

  const serviceWorkerRegistration = await navigator.serviceWorker.getRegistration()
    ?? await registerServiceWorker();

  notifications = await serviceWorkerRegistration.getNotifications();
  displayNotifications();

  // A message is posted when a new notification is received
  navigator.serviceWorker.addEventListener('message', (e: MessageEvent<Notification>) => {
    notifications.push(e.data);
    displayNotifications();
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
}

(async () => {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    console.error('No service worker or push manager support');
    return;
  }

  const askPermissionBtn = document.getElementById('ask-permission');
  if (!askPermissionBtn) return;

  if (Notification.permission !== 'granted') {
    askPermissionBtn.addEventListener('click', async () => {
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        console.error('No permission for notifications');
        return;
      };

      initialize(askPermissionBtn);
    });
  } else {
    initialize(askPermissionBtn);
  }
})();
