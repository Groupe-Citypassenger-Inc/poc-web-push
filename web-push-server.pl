use Mojolicious::Lite;
use Mojo::File;
use Mojo::UserAgent;
use JSON::XS;
use HTTP::Request::Webpush;
use File::Path qw(make_path);
use Dotenv -load;
use Data::Dumper;
use Crypt::PK::ECC;

sub notify {
  my ($c, $subscriptions, $regex, $log) = @_;

  my $payload = { 
    title => "Nouvelle alerte \"$regex\" !",
    body => "Log: \"$log\"",
    data => {
      log => $log,
      regex => $regex,
    },
  };
  my $message = HTTP::Request::Webpush->new();
  
  $message->subject('mailto:hello@citypassenger.com');
  $message->content(encode_json($payload));
  $message->authbase64($ENV{PUBLIC_KEY}, $ENV{PRIVATE_KEY});
  $message->header('TTL' => 60 * 60);

  my $ua = Mojo::UserAgent->new;

  foreach my $subscription (@{$subscriptions}) {
    $message->subscription($subscription);
    $message->encode();

    my %headers_hash;
    foreach my $field_name ($message->headers->header_field_names) {
      $headers_hash{$field_name} = $message->headers->header($field_name);
    }

    my $tx = $ua->build_tx(POST => $subscription->{endpoint} => \%headers_hash => $message->content);
    my $res = $ua->start($tx)->result;

    if ($res->is_success) {
       $c->app->log->info("Push notification sent for $regex");
    } else {
      $c->app->log->warn("Failed to send push notification: " . $res->message);
      $c->rendered(500);
    }
  }
}

sub get_subscribtions {
  my $group_name = shift;

  my $subscription_file = "subscriptions/$group_name.json";
  my $file = Mojo::File->new($subscription_file);

  return ( undef, $file ) unless (-e $file->path);

  my $subscriptions_data = $file->slurp;
  my $subscriptions = decode_json($subscriptions_data);

  return ( $subscriptions, $file );
}

post '/wps/subscribe' => sub {
  my $c = shift;

  my $group_name = $c->param('groupName');
  my $regex = $c->param('regex');
  my $subscription = $c->param('subscription');

  my ($subscriptions, $file) = get_subscribtions($group_name);

  print $regex;

  unless ($subscriptions) {
    $c->app->log->info("Creating new subscription file for group $group_name");
    make_path($file->dirname);    
    $subscriptions = {};
  }

  push @{$subscriptions->{$regex}}, decode_json($subscription);

  $file->spurt(encode_json($subscriptions));

  $c->rendered(200);
};

post '/wps/get-subscriptions' => sub {
  my $c = shift;
  my $group_name = $c->param('groupName');
  my $json_subscription = $c->param('subscription');
  my $subscription = decode_json($json_subscription);

  my ($subscriptions) = get_subscribtions($group_name);
  unless ($subscriptions) {
      $c->render( json => [] );
      return;
  }

  my @matching_keys;

  # Iterate over the keys and values in the data hash
  while (my ($key, $value) = each %$subscriptions) {
    foreach my $elem (@$value) {
      if ($elem->{endpoint} eq $subscription->{endpoint}) {
        push @matching_keys, $key;
        last;  
      }
    }
  }

  $c->render( json => \@matching_keys );
};

del '/wps/delete-subscription' => sub {
  my $c = shift;
  my $group_name = $c->param('groupName');
  my $regex = $c->param('regex');
  my $json_subscription = $c->param('subscription');
  my $subscription = decode_json($json_subscription);

  my ($subscriptions, $file) = get_subscribtions($group_name);
  unless ($subscriptions) {
    $c->app->log->info("No subscriptions found for $group_name");
    $c->rendered(404);
  }

  my $regex_subscription = $subscriptions->{$regex};

  print Dumper($regex_subscription);

  my $index_to_delete = -1;
  for (my $i = 0; $i < @$regex_subscription; $i++) {
    if ($regex_subscription->[$i]->{endpoint} eq $subscription->{endpoint}) {
      $index_to_delete = $i;
      last;
    }
  }

  unless ($index_to_delete >= 0) {
    $c->app->log->info("No subscriptions found for regex pattern $regex in group $group_name");
    $c->rendered(404);
  }

  splice(@$regex_subscription, $index_to_delete, 1);

  $file->spurt(encode_json($subscriptions));

  $c->rendered(200);
};

# DEMO function - To remove
post '/wps/simulate-log' => sub {
  my $c = shift;
  my $log = $c->param('log');
  my $group_name = 'dev-nathan';

  my ($subscriptions) = get_subscribtions($group_name);

  unless ($subscriptions) {
    $c->rendered(200);
  }

  my @matching_keys = grep { $log =~ /$_/ } keys %$subscriptions;

  foreach my $key (@matching_keys) {
    notify($c, $subscriptions->{$key}, $key, $log);
  }

  $c->rendered(200);
};

app->start;
