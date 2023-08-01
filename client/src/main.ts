import './style.css';

interface Alert {
  id: number,
  name: string,
  regex: string;
  is_subscribe: 1 | 0,
}

let alerts = [] as Alert[];
let notifications = [] as Notification[];

function setupNotificationTest(serviceWorkerRegistration: ServiceWorkerRegistration) {
  const tryNotificationButton = document.getElementById('try-notification');
  if (!tryNotificationButton) return;
  tryNotificationButton.addEventListener('click', () => {
    const testNotification: NotificationOptions = {
      icon: './android-chrome-192x192.png',
      body: 'Ceci est une notification de test',
      data: { date: new Date() },
    }
    serviceWorkerRegistration.showNotification('Test notification', testNotification);
    notifications.push(new Notification('Test notification', testNotification));
    displayNotifications();
  });
}

async function displayNotifications() {
  const noNotificationEl = document.getElementById('no-notification');
  const notificationsEl = document.getElementById('notifications');

  if (!notificationsEl || !noNotificationEl) return;

  noNotificationEl.style.display = notifications.length === 0 ? 'block' : 'none';
  notificationsEl.innerHTML = '';

  notifications.forEach((notification) => {
    const li = document.createElement('li');
    li.textContent = `${notification.data?.date?.toLocaleString()} - ${notification.body}`;
    notificationsEl.appendChild(li);
  });
}

async function unsubscribe(subscription: PushSubscription, alert: Alert) {
  fetch(`./wps/unsubscribe/${alert.id}`, {
    method: 'POST',
    body: new URLSearchParams({
      subscription: JSON.stringify(subscription.toJSON()),
    })
  }).then(() => {
    alert.is_subscribe = 0;
    displayAlerts(subscription);
  });
}

function subscribe(subscription: PushSubscription, alert: Alert) {
  fetch(`./wps/subscribe/${alert.id}`, {
    method: 'POST',
    body: new URLSearchParams({
      subscription: JSON.stringify(subscription.toJSON()),
    })
  }).then(() => {
    alert.is_subscribe = 1;
    displayAlerts(subscription);
  });
}

function createAlert(subscription: PushSubscription, alert: Partial<Alert>) {
  fetch(`./wps/alert`, {
    method: 'POST',
    body: new URLSearchParams({
      group_name: 'dev-sandbox',
      regex: alert.regex,
      name: alert.name,
    })
  })
  .then((resp) => resp.text())
  .then((id) => {
    alert.id = Number(id);
    alerts.push(alert as Alert);
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
    button.innerText = alert.is_subscribe ? 'Ne plus me notifier sur ce navigateur' : 'Me notifier sur ce navigateur';
    button.onclick = () => (alert.is_subscribe ? unsubscribe : subscribe)(subscription, alert);
    const li = document.createElement('li');
    const notifyText = alert.is_subscribe ? 'Notifié sur ce navigateur' : 'Non notifié sur ce navigateur';
    li.textContent = `"${alert.name}" (${notifyText})`;
    li.appendChild(button);
    alertsEl.appendChild(li);
  })
}

function fetchAndDisplayAlerts(subscription: PushSubscription) {
  fetch('./wps/register', {
    method: 'POST',
    body: new URLSearchParams({
      subscription: JSON.stringify(subscription.toJSON()),
      group_name: 'dev-sandbox',
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
    const name = (form.name as any).value as string;
    const regex = form.regex.value as string;
    const newAlert: Partial<Alert> = { name, regex, is_subscribe: 0 };
    createAlert(subscription, newAlert);
  }
}

function handleSimulateLogForm() {
  const form = document.getElementById('log-form');
  if (!form) return;

  form.onsubmit = async (event) => {
    event.preventDefault();
    const form = event.target as HTMLFormElement;
    const newLog = form.log.value;
    fetch('./wps/simulate-log', {
      method: 'POST',
      body: new URLSearchParams({
        groupName: 'dev-sandbox',
        log: newLog,
      })
    });
  }
}

function handleRegeneratePubKeyForm(subscription: PushSubscription, askPermissionBtn: HTMLElement) {
  const form = document.getElementById('regen-pub-key');
  if (!form) return;

  form.onsubmit = async (event) => {
    event.preventDefault();
    const form = event.target as HTMLFormElement;
    const newKey = form.pubkey.value;
    subscription.unsubscribe();
    initialize(askPermissionBtn, newKey);
  };
}

async function initialize(askPermissionBtn: HTMLElement, pubkey = __APP_PUSH_PUBLIC_KEY__) {
  const app = document.getElementById('app');
  if (!app) return;
  app.style.display = 'block';
  askPermissionBtn.style.display = 'none';

  const registerServiceWorker = async (): Promise<ServiceWorkerRegistration> => {
    console.log('Registering service worker');
    await navigator.serviceWorker.register('./service-worker.js');
    return await navigator.serviceWorker.ready;
  }

  const serviceWorkerRegistration = await navigator.serviceWorker.getRegistration()
    ?? await registerServiceWorker();

  setupNotificationTest(serviceWorkerRegistration);

  notifications = await serviceWorkerRegistration.getNotifications();
  displayNotifications();

  // A message is posted when a new notification is received
  navigator.serviceWorker.addEventListener('message', (e: MessageEvent<Notification>) => {
    notifications.push(e.data);
    displayNotifications();
  });

  const createSubscription = () => {
    console.log('Creating subscription');
    return serviceWorkerRegistration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: pubkey,
    }).catch((err) => alert(err.message));
  }

  const subscription = await serviceWorkerRegistration.pushManager.getSubscription()
    ?? await createSubscription();

  if (!subscription) return;

  fetchAndDisplayAlerts(subscription);
  handleCreateAlertForm(subscription);
  handleSimulateLogForm();
  handleRegeneratePubKeyForm(subscription, askPermissionBtn);
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
