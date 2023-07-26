#!/usr/bin/env perl
use strict;
use utf8;
use lib '.';
use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use Dotenv -load;
use Wps::SendNotification;

# Add controller path to the app
push @{app->routes->namespaces}, 'Wps';

helper sqlite => sub { 
  state $sqlite = Mojo::SQLite->new('sqlite:web-push-server.db');
  $sqlite->on(connection => sub ($sql, $dbh) {
    $dbh->do('PRAGMA foreign_keys = ON');
  });
  return $sqlite;
};

plugin Minion => { SQLite => app->sqlite };

app->minion->add_task(notify => \&Wps::SendNotification::send_notification);

# TODO: Require local_request
my $subscription_controller = app->routes->any('/wps')->to(controller => 'Subscription');
$subscription_controller->post('/alert')->to(action => 'create_alert');
$subscription_controller->delete('/alert/:id')->to(action => 'delete_alert');
$subscription_controller->post('/register')->to(action => 'register_and_get_alerts');
$subscription_controller->post('/subscribe/:id')->to(action => 'subscribe');
$subscription_controller->post('/unsubscribe/:id')->to(action => 'unsubscribe');

# TODO: Require admin_request
my $notify_controller = app->routes->any('/wps/notify')->to(controller => 'Notifier');
$notify_controller->get('/:group_name')->to(action => 'get_regex_subsbscriptions');
$notify_controller->post('/:id')->to(action => 'notify');

app->start;
