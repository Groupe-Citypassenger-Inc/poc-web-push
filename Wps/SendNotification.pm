package Wps::SendNotification;

use strict;
use utf8;
use Mojo::UserAgent;
use HTTP::Request::Webpush;
use Crypt::PK::ECC;
use Mojo::JSON qw(encode_json);

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
