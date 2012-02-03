package t::lib::TestApp;

use Dancer;
use Dancer::Plugin::Database;


hook database_connected => sub {
    my $dbh = shift;
    vars->{connecthookfired} = $dbh; 

};

get '/connecthookfired' => sub { 
    my $database = database();
    # If the hook fired, it'll have squirreled away a reference to the DB handle
    # for us to look for.
    my $h = vars->{connecthookfired};
    if (ref $h && $h->isa('DBI::db')) {
        return 1;
    } else {
        return 0;
    }
};

my $last_db_error;
hook 'database_error' => sub {
    $last_db_error = $_[0];
};

get '/errorhookfired' => sub {
    database->do('something silly');
    return $last_db_error ? 1 : 0;
};


get '/prepare_db' => sub {

    my @sql = (
        q/create table users (id INTEGER, name VARCHAR, category VARCHAR)/,
        q/insert into users values (1, 'sukria', 'admin')/,
        q/insert into users values (2, 'bigpresh', 'admin')/,
        q/insert into users values (3, 'badger', 'animal')/,
        q/insert into users values (4, 'bodger', 'man')/,
        q/insert into users values (5, 'mousey', 'animal')/,
    );

    database->do($_) for @sql;
    'ok';
};

get '/' => sub {
    my $sth = database->prepare('select count(*) from users');
    $sth->execute;
    my $total_users = $sth->fetch();
    $total_users->[0];
};

get '/user/:id' => sub {
    my $sth = database->prepare('select * from users where id = ?');
    $sth->execute( params->{id} );
    my $user = $sth->fetch();
    $user->[1] || "No such user";
};

del '/user/:id' => sub {
    my $sth = database->prepare('delete from users where id = ?');
    $sth->execute( params->{id} );
    'ok';
};


# Routes to exercise some of the extended features:
get '/quick_insert/:id/:name' => sub {
    database->quick_insert('users',
        { id => params->{id}, name => params->{name}, category => 'user' },
    );
    'ok';
};

get '/quick_update/:id/:name' => sub {
    database->quick_update('users',
        { id => params->{id}     },
        { name => params->{name} },
    );
    'ok';
};

get '/quick_delete/:id' => sub {
    database->quick_delete('users', { id => params->{id} });
    'ok';
};

get '/quick_select/:id' => sub {
    my $row = database->quick_select('users', { id => params->{id} });
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/quick_select/:id/:parm' => sub {
    my $row = database->quick_select('users', { id => params->{id} }, 
         [ 'id', params->{parm} ]);
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/quick_lookup/:name' => sub {
    my $id = database->quick_lookup('users', { name => params->{name} },
        'id');

    return $id;
};

get '/complex_where/:id' => sub {
    my $row = database->quick_select(
        'users', { id => { 'gt' => params->{id} } }
    );
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/complex_not/:id' => sub {
    my $row = database->quick_select('users', { category => { 'is' => undef, 'not' => 1 } });
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/set_op/:id' => sub {
    my $row = database->quick_select('users', { id => [ params->{id} ] });
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/quick_select_many' => sub {
        my @users = database->quick_select('users', {  category => 'admin' });
        return join ',', sort map { $_->{name} } @users;
};

# e.g. /quick_select_specific_cols/foo should return col 'foo'
#  or  /quick_select_specific_cols/foo/bar returns foo:bar
get '/quick_select_specific_cols/**' => sub {
    my $out;
    my $cols = (splat)[0];
    my @users = database->quick_select('users', {}, { columns => $cols });
    for my $user (@users) {
        $out .= join(':', @$user{@$cols}) . "\n"; 
    }
    return $out;
};

get '/quick_select_with_limit/:limit' => sub {
    my $limit = params->{limit};
    my @users = database->quick_select('users', {}, { limit => $limit });
    return scalar @users;
};

get '/quick_select_sorted' => sub {
    my @users = database->quick_select('users', {}, { order_by => 'name' });
    return join ':', map { $_->{name} } @users;
};
get '/quick_select_sorted_rev' => sub {
    my @users = database->quick_select(
        'users', {}, { order_by => { desc => 'name' } }
    );
    return join ':', map { $_->{name} } @users;
};



# Check we can get a handle by passing a hashref of settings, too:
get '/runtime_config' => sub {
    my $dbh = database({ driver => 'SQLite', database => ':memory:'});
    $dbh ? 'ok' : '';
};

# Check we get the same handle each time we call database()
get '/handles_cached' => sub {
    database() eq database() and return "Same handle returned";
};


# Check that the database_connection_lost hook fires when we force a db handle
# to go away:
hook database_connection_lost => sub { vars->{lost_connection} = 1; };
get '/database_connection_lost_fires' => sub {
    vars->{lost_connection} = 0;
    database()->disconnect;
    # We set connection_check_threshold to 0.1 at the start, so wait a second
    # then check that the code detects the handle is no longer connected and
    # triggers the hook
    sleep 1;
    my $handle = database();
    return vars->{lost_connection};
};


1;
