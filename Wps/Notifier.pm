package Wps::Notifier;
use Data::Dumper;
use Mojo::JSON qw(decode_json);

use Mojo::Base 'Mojolicious::Controller', -signatures;

sub notify ($self) {
  my $alert_id = $self->param('id');
  my $log = $self->param('log');

  unless ($alert_id && $log) {
    return $self->render(text => 'Missing required parameters', status => 400);
  }

  # Render as fast as possible 
  $self->rendered(202);

  my $result = $self->sqlite->db->query('
    SELECT a.name, a.group_name, s.browser_info
    FROM alerts a, subscriptions s, alerts_subscriptions alsub
    WHERE a.id = ?
    AND alsub.alert_id = a.id AND alsub.subscription_id = s.id
  ', $alert_id);

  unless ($result) {
    return $self->app->warn("Failed to get subscriptions for alert #" . $alert_id);
  }
  
  my $result_hashes = $result->hashes;

  # Return if no one to notify
  unless ($result_hashes->size) {
    return;
  }

  my $first_row = $result_hashes->first;
  my $alert = {
    group_name => $first_row->{group_name},
    name => $first_row->{name},
    id => $alert_id,
  };

  my $subcriptions = $result_hashes->map(sub { decode_json $_->{browser_info} })->to_array;

  $self->minion->enqueue('notify', [$subcriptions, $alert, $log]);
}

sub get_regex_subsbscriptions ($self) {
  my $group_name = $self->param('group_name');

  unless ($group_name) {
    return $self->render(text => 'Missing group_name parameter', status => 400);
  }

  my $result = $self->sqlite->db->select('alerts', ['regex', 'id'], { group_name => $group_name });

  unless ($result) {
    return $self->render(text => 'Cannot get subscriptions', status => 500);
  }

  my $regex_id_map = $result->hashes->reduce(sub { 
    $a->{ $b->{regex} } = $b->{id}; $a 
  }, {});

  $self->render(json => $regex_id_map, status => 200);
}

1;
