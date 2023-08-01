# Web Push POC

Proof of concept for regex log notification subscribtion using the web push technology.

## How it works

### Client side

First user must allow notifications. Some browser, like safari, require user interaction to prompt the ask so a dedicated button is used. While notifications are not allowed by client nothing is done.

Notification reception is handled by a service worker. Service worker is a dedicated file that run in the browser background. It updates itself automatically each 24h. It use a dedicated scope that allows specific usage (https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerGlobalScope). It define 2 events handler, one when notification is received, and the other when the notifications is clicked (see code).

A service worker is registered if it doesnt exist on app startup.
Notification subscription are linked to the service worker. If a  service worker is unregistred, all existing subscription and notififcation are deleted.

Once service worker is retrieved or created, an event is attached to it to be able to receive message from it on a new notification.

The subscription is then retrieved or created from the service worker. A subscription is an object with an endpoint to notify and auth keys. It need a public VAPID key (from the server) to be created.

Once evrything is set (serviceworker and subscription), the client must symply send it subscription ton the server in order to be notifyed in the future.

### Server side

Notifications are send using [HTTP::Request::Webpush](https://metacpan.org/pod/HTTP::Request::Webpush). Server must first store subscription objects (from clients) and then can use Webpush to send notification to the wanted subscriptions. In order to encode the payload and provide authentification header it must have a private and and public (the same used in subscription creation) VAPID keys.

Subscriptions are stored in a SQLite Database following this schema :

```sql
CREATE TABLE IF NOT EXISTS alerts (
    id INTEGER PRIMARY KEY,
    group_name TEXT NOT NULL,
    name TEXT NOT NULL,
    regex TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id INTEGER PRIMARY KEY,
    browser_info JSON NOT NULL
);

CREATE TABLE IF NOT EXISTS alerts_subscriptions (
    alert_id INTEGER NOT NULL,
    subscription_id INTEGER NOT NULL,
    PRIMARY KEY (alert_id, subscription_id),
    FOREIGN KEY (alert_id) REFERENCES alerts(id) ON DELETE CASCADE,
    FOREIGN KEY (subscription_id) REFERENCES subscriptions(id) ON DELETE CASCADE
);
```

In order to make `ON DELETE CASCADE` works it's necessary to specify:

```sql
PRAGMA foreign_keys = ON;
```

## Installation

### Install Perl dependencies

```shell
# New
cpanm HTTP::Request::Webpush
# Should already be installed
cpanm JSON::XS;
cpanm Mojolicious::Lite;
# Optional
cpanm Dotenv;
```

### Generate Public & Private VAPID keys

- Using openssl

Keys for notification are in  https://www.rfc-editor.org/rfc/rfc7518
and should use:
```
| ES256        | ECDSA using P-256 and SHA-256 | Recommended+       |
```
The Payload encryption use GCM ( gallois counter mode ) *
For the client the key are stored in base64 url form.

To generate a ECDSA key (using curve name prime256v1 instead of secp256r1 because ... ):
  ```
  openssl ecparam -out vapid_v2.pem -name prime256v1 -genkey
  ```

Then to extract the key

```
$ openssl asn1parse -in p256v1SamplePKEY.pem
    0:d=0  hl=2 l= 119 cons: SEQUENCE
    2:d=1  hl=2 l=   1 prim: INTEGER           :01
    5:d=1  hl=2 l=  32 prim: OCTET STRING      [HEX DUMP]:FBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxA6
   39:d=1  hl=2 l=  10 cons: cont [ 0 ]
   41:d=2  hl=2 l=   8 prim: OBJECT            :prime256v1
   51:d=1  hl=2 l=  68 cons: cont [ 1 ]
   53:d=2  hl=2 l=  66 prim: BIT STRING
$ openssl ec -in p256v1SamplePKEY.pem  -text
will give you the info but may botched the ouput
# echo note that
$ perl -e '@array = ( "aabbccdd" =~ m/../g );' -e 'print $array[1]."\n";'
bb
```
so the perl script, getit.pl:
```
use MIME::Base64;
$/ = undef
my @karr = ( <> =~ m/../g );
my $k = '';
foreach $a (@karr) {
  my $x =  pack 'H*', $a;
  $k .= $x;
}
print MIME::Base64::encode_base64url($k);
```
should work and give you the ( private key )

```
$ printf 'FBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxA6' | perl getit.pl
```

There s other way to do that, for the public part, dont ask y but getting the value is a bit different
```
openssl ec -in p256v1SamplePKEY.pem  -pubout >  p256v1SamplePUB
$ openssl asn1parse -in p256v1SamplePUB
    0:d=0  hl=2 l=  89 cons: SEQUENCE
    2:d=1  hl=2 l=  19 cons: SEQUENCE
    4:d=2  hl=2 l=   7 prim: OBJECT            :id-ecPublicKey
   13:d=2  hl=2 l=   8 prim: OBJECT            :prime256v1
   23:d=1  hl=2 l=  66 prim: BIT STRING
$ openssl ec -pubin -in p256v1SamplePUB -noout -text
read EC key
Private-Key: (256 bit)
pub:
    04:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:
    XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:
    XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:
    XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:
    XX:XX:XX:XX:45
# remove the white space and use that buffer
$ perl -MMIME::Base64 -e '$pk = ''; foreach $x (split /:/, "04:xxx:45") { $pk .= pack 'H*', $x }; MIME::Base64::encode_base64url($pk);' 
```

This works and give you a key.

The baes64 encoded key is fixed in length afaik, 
43 character for the private part
and 87 for the public one.

Following/Below methods ARE NOT RECOMMENDED

- Using npx

  ```
  npx web-push generate-vapid-keys
  ```

- Using browser 

  https://www.stephane-quantin.com/en/tools/generators/vapid-keys

### Set env

Public key must be share with front (api incoming).
For the server there is 2 ways :

- With .env file

  ```conf
  PRIVATE_KEY=...
  PUBLIC_KEY=...
  ```

  Dotenv should be use and loaded in perl

  ```pl
  use Dotenv -load;
  ```

- With env profile

  ```shell
  echo export PRIVATE_KEY=... >> ~/.profile
  echo export PUBLIC_KEY=... >> ~/.profile
  ```

### Setup the database

Create `web-push-server.db` and use the schema.
