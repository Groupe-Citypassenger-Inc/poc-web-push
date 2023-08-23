package Wps::SendNotification;

use strict;
use utf8;
use Mojo::UserAgent;
use HTTP::Request::Webpush;
use Crypt::PK::ECC;
use Mojo::JSON qw(encode_json);

use URI;
use IPC::Cmd qw[run_forked];
use Digest::SHA 'hmac_sha256';
use Net::SSLeay;
Net::SSLeay::randomize();
use Crypt::AuthEnc::GCM 'gcm_encrypt_authenticate';

my $cek_info='Content-Encoding: aes128gcm'.chr(0);
my $nonce_info='Content-Encoding: nonce'.chr(0);

sub my_do_notify {
  my ($payload, $subscription) = @_;
  my $ua = Mojo::UserAgent->new;
  my $endpoint = URI->new($subscription->{endpoint});
  my $aud = $endpoint->scheme.'://'.$endpoint->host;

  # my $salt=random_bytes(16);
  Net::SSLeay::RAND_bytes(my $salt,16);

  my $sk=Crypt::PK::ECC->new();
  my $ua_public = MIME::Base64::decode_base64url($subscription->{'keys'}->{'p256dh'});
  $sk->import_key_raw($ua_public, 'secp256r1');

  my $pk=Crypt::PK::ECC->new();
  $pk->generate_key('prime256v1'); # those could maybe be reused

  my $pub_signkey=$pk->export_key_raw('public');
  my $sec_signkey=$pk->export_key_raw('private');

  my $ecdh_secret = $pk->shared_secret($sk); # wut ?
  my $auth_secret= MIME::Base64::decode_base64url($subscription->{'keys'}->{'auth'});

  # my $prk = $self->_hkdf($auth_secret, $ecdh_secret, $key_info,32);
  my $key_info='WebPush: info'.chr(0).$ua_public.$pub_signkey;
  my $salted = hmac_sha256( $ecdh_secret, $auth_secret );
  my $prk = substr( hmac_sha256($key_info, chr(1), $salted), 0 , 32);

  # my $cek = $self->_hkdf($salt,$prk,$cek_info,16);
  $salted = hmac_sha256($prk, $salt);
  my $cek = substr( hmac_sha256( $cek_info, chr(1), $salted), 0, 16);

  # my $nonce= $self->_hkdf($salt, $prk,$nonce_info,12);
  my $nonce =  substr( hmac_sha256( $nonce_info , chr(1), $salted), 0, 12);

  $payload = JSON->new->utf8->encode($payload);
  my ($body, $tag) = gcm_encrypt_authenticate('AES', $cek, $nonce, '', $payload."\x02\x00");
  my $content = $salt."\x00\x00\x10\x00\x41".$pub_signkey.$body.$tag;


  my $jwtp = '{"aud":"'.$aud.'","exp":'.(time+100).',"sub":"mailto:hello@citypassenger.com"}';
  my $jose = run_forked( "jose jws sig -I - -k ~/key.jwk -o -"
            , { child_stdin => $jwtp });
  my $jwt = JSON->new->utf8->decode($jose->{stdout});
  my $auth = join( '.', ($jwt->{protected},$jwt->{payload},$jwt->{signature}) );
  my $headers = {
    'Content-Type' => 'application/octet-stream'
    ,
    'Host' => $endpoint->host
    ,
    'Content-Length' => length $content
    ,
    'Authorization' => 'WebPush '.$auth
    ,
    'Crypto-Key' => 'p256ecdsa='.$ENV{publicKey}
    ,
    'Content-Encoding' => 'aes128gcm'
    ,
    'Accept-Encoding' => 'gzip'
    ,
    'TTL' => 3600
  };
  my $tx = $ua->build_tx(POST => $endpoint->as_string
                              => $headers
                              => $content);
  return ($ua, $tx);
}


sub send_notification {
  my ($job, @args) = @_;
  my ($subscriptions, $alert, $log) = @args;

  my $payload = { 
    title => $alert->{name},
    body => "Log: \"$log\"",
    data => {
      log => $log,
      alert_id => $alert->{id},
      group_name => $alert->{group_name},
    },
  };

  my $alert_info = $alert->{group_name} . ": \"" . $alert->{name} . "\" #" . $alert->{id};

  foreach my $subscription (@{$subscriptions}) {
    my $message = HTTP::Request::Webpush->new();
    $message->subject('mailto:hello@citypassenger.com');
    $message->content(encode_json($payload));
    $message->authbase64($ENV{PUBLIC_KEY}, $ENV{PRIVATE_KEY});
    $message->header('TTL' => 60 * 60);
   
    my $ua = Mojo::UserAgent->new;

    $message->subscription($subscription);
    $message->encode();

    my %headers_hash;
    foreach my $field_name ($message->headers->header_field_names) {
      $headers_hash{$field_name} = $message->headers->header($field_name);
    }

    my $tx = $ua->build_tx(POST => $subscription->{endpoint} => \%headers_hash => $message->content);
    my $res = $ua->start($tx)->result;

    if ($res->is_success) {
      $job->app->log->info("Push notification sent for $alert_info to " . $subscription->{endpoint});
    } else {
      $job->app->log->warn("Failed to send push notification for $alert_info to " . $subscription->{endpoint} . ": " . $res->message);
    }

    # Status code 410 means the subscription no longer exist and should be removed
    unless ($res->code == 410) {
      next;
    }

    my $result = $job->app->sqlite->db->delete('subscriptions', { browser_info => { -json => $subscription } });
    if ($result) {
      $job->app->log->info("Successfully delete subscriptions " . $subscription->{endpoint});
    } else {
      $job->app->log->warn("Failed to delete subscriptions " . $subscription->{endpoint});
    }
  }
}

1;
