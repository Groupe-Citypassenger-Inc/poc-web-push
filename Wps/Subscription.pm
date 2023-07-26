package Wps::Subscription;
use Mojo::JSON qw(decode_json);
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub create_alert ($self) {
  my $group_name = $self->param('group_name');
  my $alert_name = $self->param('name');
  my $alert_regex = $self->param('regex');

  unless ($group_name && $alert_name && $alert_regex) {
    return $self->render(text => 'Missing required parameters', status => 400);
  }

  my $result = $self->sqlite->db->insert('alerts', {
    group_name => $group_name,
    name => $alert_name,
    regex => $alert_regex
  });

  unless ($result) {
    return $self->render(text => 'Cannot create alert', status => 500);
  }

  $self->render(text => $result->last_insert_id, status => 201);
}

sub delete_alert ($self) {
  my $alert_id = $self->param('id');
  my $group_name = $self->param('group_name');

  unless ($alert_id) {
    return $self->render(text => 'Missing required parameters', status => 400);
  }

  # group_name is not mandatory, but it's a security that assure that the group_name is known to delete alert
  my $result = $self->sqlite->db->delete('alerts', { id => $alert_id, group_name => $group_name });

  unless ($result) {
    return $self->render(text => 'Cannot delete alert', status => 500);
  }

  $self->rendered(200);
}

sub subscribe ($self) {
  my $alert_id = $self->param('id');
  # Use subscription instead of subscription_id to make sure the request come from the user
  my $user_subscription_str = $self->param('subscription');

  unless ($alert_id && $user_subscription_str) {
    return $self->render(text => 'Missing required parameters', status => 400);
  }

  my $user_subscription = decode_json $user_subscription_str;

  my $existing_subscription = $self->sqlite->db->select(
    'subscriptions', undef, { browser_info => { -json => $user_subscription } }
  )->hash;

  unless ($existing_subscription) {
    return $self->render(text => 'Unknown subscription', status => 401);
  }

  my $result = $self->sqlite->db->insert('alerts_subscriptions', {
    alert_id => $alert_id,
    subscription_id => $existing_subscription->{id}
  });

  unless ($result) {
    return $self->render(text => 'Cannot create subscription', status => 500);
  }

  $self->rendered(200);
}

sub unsubscribe ($self) {
  my $alert_id = $self->param('id');
  # Use subscription instead of subscription_id to make sure the request come from the user
  my $user_subscription_str = $self->param('subscription');

  unless ($alert_id && $user_subscription_str) {
    return $self->render(text => 'Missing required parameters', status => 400);
  }

  my $user_subscription = decode_json $user_subscription_str;

  my $existing_subscription = $self->sqlite->db->select(
    'subscriptions', undef, { browser_info => { -json => $user_subscription } }
  )->hash;

  unless ($existing_subscription) {
    return $self->render(text => 'Unknown subscription', status => 401);
  }

  my $result = $self->sqlite->db->delete('alerts_subscriptions', {
    alert_id => $alert_id,
    subscription_id => $existing_subscription->{id}
  });

  unless ($result) {
    return $self->render(text => 'Cannot delete subscription', status => 500);
  }

  $self->rendered(200);
}

sub register_and_get_alerts ($self) {
  my $group_name = $self->param('group_name');
  my $user_subscription_str = $self->param('subscription');

  unless ($user_subscription_str && $group_name) {
    return $self->render(text => 'Missing required parameters', status => 400);
  }

  my $user_subscription = decode_json $user_subscription_str;

  my $existing_subscription = $self->sqlite->db->select(
    'subscriptions', undef, { browser_info => { -json => $user_subscription } }
  )->hash;
  my $subscription_id = $existing_subscription ? $existing_subscription->{id} : undef;

  # Register the subscription if not already in db
  unless ($subscription_id) {
    my $result = $self->sqlite->db->insert(
      'subscriptions', { browser_info => { -json => $user_subscription } }
    );
    $subscription_id = $result->last_insert_id;
  }

  my $result = $self->sqlite->db->query('
    SELECT a.ID, a.name, a.regex,
      CASE WHEN subs.subscription_id IS NOT NULL THEN 1 ELSE 0 END AS is_notified
    FROM alerts a
    LEFT JOIN alerts_subscriptions subs
    ON a.id = subs.alert_id AND subs.subscription_id = ?
    WHERE group_name = ?
  ', ($subscription_id, $group_name));

  unless ($result) {
    return $self->render(text => 'Cannot register subscription', status => 500);
  }

  $self->render(json => $result->hashes, status => 200);
} 

1;
