package Orrery;

use strict;
use warnings;

use Astro::Coords;
use Astro::Coords::Angle;
use Astro::Coords::Planet;
use Astro::MoonPhase;
use Astro::Telescope;
use Curses;
use I18N::Langinfo qw(langinfo CODESET);
use Math::Trig qw(pi deg2rad rad2deg);
use POSIX qw(round strftime);

our $VERSION = '1.00';


my %abbrevs = (moon    => 'L',
               sun     => 'S',
               mercury => 'M',
               venus   => 'v',
               mars    => 'm',
               jupiter => 'j',
               saturn  => 's',
               uranus  => 'u',
               neptune => 'n');
my %symbols = (moon    => "\x{263D}",
               sun     => "\x{2609}",
               mercury => "\x{263f}",
               venus   => "\x{2640}",
               mars    => "\x{2642}",
               jupiter => "\x{2643}",
               saturn  => "\x{2644}",
               uranus  => "\x{2645}",
               neptune => "\x{2646}");
my $unicode = langinfo(CODESET) =~ /^utf|^ucs/i;

sub new {
    my ($class, %args) = @_;
    my $self = {};

    my $lat = $args{lat};
    my $long = $args{long};
    $lat = Astro::Coords::Angle->new($lat, units => 'degrees')
        if !$lat->isa('Astro::Coords::Angle');
    $long = Astro::Coords::Angle->new($long, units => 'degrees')
        if !$long->isa('Astro::Coords::Angle');

    $self->{telescope} =
        Astro::Telescope->new(Name => 'Orrery',
                              Lat  => $lat,
                              Long => $long,
                              Alt  => $args{alt} || 0);

    $self->{view_az} = $args{azimuth} || $lat > 0 ? pi : 0;
    $self->{view_el} = $args{elevation} || 0;
    $self->{view_width} = 0.95;
    $self->{view_height} = 1;

    my (%planets, @planet_order);
    foreach my $planet_name (@Astro::Coords::Planet::PLANETS) {
        my $planet = Astro::Coords->new(planet => $planet_name);
        $planet->telescope($self->{telescope});

        $planets{$planet_name} = $planet;
        push @planet_order, $planet_name;
    }
    $self->{planets} = \%planets;
    $self->{planet_order} = \@planet_order;

    $self->{win} = Curses->new;
    curs_set 0;

    my $get_size = sub {
        my ($maxy, $maxx);
        $self->{win}->getmaxyx($maxy, $maxx);
        $self->{maxyx} = [$maxy, $maxx];
    };
    &{$get_size}();
    my $winch = sub {
        endwin;
        refresh;
        &{$get_size}();
        draw($self);
    };
    $SIG{WINCH} = $winch;

    return bless $self, $class;
}

sub DESTROY {
    my $self = shift;

    endwin;
}

sub azel_to_yx {
    my $self = shift;
    my $az = shift;
    my $el = shift;

    my ($maxy, $maxx) = @{$self->{maxyx}};
    my $view_az = $self->{view_az};
    my $view_el = $self->{view_el};
    my $view_width = $self->{view_width};
    my $view_height = $self->{view_height};

    if ($view_width == 1 && $view_az - $az == pi) {
        return -$maxx;
    }

    my $y = round($maxy / 2 - (1 / $view_height) * (($el / (pi / 2)) - ($view_el / (pi / 2))) * ($maxy / 2));
    my $x = round($maxx / 2 + (1 / $view_width) * (($az / (pi * 2)) - ($view_az / (pi * 2))) * $maxx);
    #my $y = round($maxy / 2 - ($el / (pi / 2)) * ($maxy / 2));
    #my $x = round(($az / (pi * 2)) * $maxx);

    return ($y, $x);
}

sub az_to_x {
    my $self = shift;
    my $az = shift;

    my ($maxy, $maxx) = @{$self->{maxyx}};
    my $view_az = $self->{view_az};
    my $view_width = $self->{view_width};

    if ($view_width == 1 && $view_az - $az == pi) {
        return -$maxx;
    }
   
    my $x = round($maxx / 2 + (1 / $view_width) * (($az / (pi * 2)) - ($view_az / (pi * 2))) * $maxx);

    return $x;
}

sub el_to_y {
    my $self = shift;
    my $el = shift;
    
    my ($maxy, $maxx) = @{$self->{maxyx}};
    my $view_el = $self->{view_el};
    my $view_height = $self->{view_height};
  
    my $y = round($maxy / 2 - (1 / $view_height) * (($el / (pi / 2)) - ($view_el / (pi / 2))) * ($maxy / 2));

    return $y;
}

sub draw {
    my $self = shift;

    my $win = $self->{win};
    $win->clear;

    $self->draw_axes;

    foreach my $planet_name (reverse @{$self->{planet_order}}) {
        $self->draw_planet($self->{planets}->{$planet_name});
    }

    $self->draw_labels;

    $win->refresh;
}

sub draw_axes {
    my $self = shift;

    my $win = $self->{win};

    my ($maxy, $maxx) = @{$self->{maxyx}};

    my $y_line = $self->el_to_y(0);
    $win->hline($y_line, 0, ACS_HLINE, $maxx);

    $win->addstring($y_line, $self->az_to_x(   -pi / 2), 'W');
    $win->addstring($y_line, $self->az_to_x(    pi / 2), 'E');
    $win->addstring($y_line, $self->az_to_x(3 * pi / 2), 'W');
    $win->addstring($y_line, $self->az_to_x(5 * pi / 2), 'E');

    foreach my $x_label (map { $self->az_to_x($_) }
                             (-3 * pi / 4,     -pi / 4,
                                   pi / 4,  3 * pi / 4,
                               5 * pi / 4,  7 * pi / 4,
                               9 * pi / 4, 11 * pi / 4)) {
        $win->hline($y_line, $x_label, ACS_PLUS, 1);
    }

    foreach my $x_line (map { $self->az_to_x($_) } (0, pi)) {
        $win->vline(0, $x_line, ACS_VLINE, $maxy);
        $win->hline($y_line, $x_line, ACS_PLUS, 1);

        foreach my $y_label (map { $self->el_to_y($_) }
                                 (-pi, pi)) {
            $win->hline($y_label, $x_line, ACS_PLUS, 1);
        }

        foreach my $y (-60, -30, 30, 60) {
            my $y_label = $self->el_to_y(deg2rad($y));
            $win->addstring($y_label, $x_line - 2, sprintf "% 2d", $y);
            $win->hline($y_label, $x_line + 1, ACS_DEGREE, 1);
        }
    }
}

sub draw_planet {
    my $self = shift;
    my $planet = shift;

    my $win = $self->{win};
    my ($maxy, $maxx) = @{$self->{maxyx}};

    my %by_value = reverse %{$self->{planets}};
    my $planet_name = $by_value{$planet};

    my ($az, $el) = $planet->azel;
    my ($y, $x) = $self->azel_to_yx($az->radians, $el->radians);
    $x %= $maxx;
    
    $win->addstring($y, $x, $unicode ? $symbols{$planet_name}
                                     : $abbrevs{$planet_name});
}

sub draw_labels {
    my $self = shift;

    my $win = $self->{win};
    my ($maxy, $maxx) = @{$self->{maxyx}};

    my ($lat_g, $lat_d, $lat_m, $lat_s) =
        $self->{telescope}->lat->components;
    my ($long_g, $long_d, $long_m, $long_s) =
        $self->{telescope}->long->components;
    my $alt = $self->{telescope}->alt;

    my $lower_left = sprintf("%3d %02d'%02d\"%s % 3d %02d'%02d\"%s  %4dm",
                             $lat_d,
                             $lat_m,
                             $lat_s,
                             $lat_g eq '+' ? 'N' : 'S',
                             $long_d,
                             $long_m,
                             $long_s,
                             $long_g eq '+' ? 'E' : 'W',
                             $alt);
    $win->addstring($maxy - 1, 0, $lower_left);
    $win->hline($maxy - 1, 3, ACS_DEGREE, 1);
    $win->hline($maxy - 1, 15, ACS_DEGREE, 1);

    my $lower_right = strftime '%F %R', localtime;
    $win->addstring($maxy - 2, $maxx - length($lower_right), $lower_right);

    my $phase = phase;
    my $phase_name = $phase < 0.02 ? 'new' :
                     $phase < 0.24 ? 'waxing crescent' :
                     $phase < 0.26 ? 'first quarter' :
                     $phase < 0.49 ? 'waxing gibbous' :
                     $phase < 0.51 ? 'full' :
                     $phase < 0.74 ? 'waning gibbous' :
                     $phase < 0.76 ? 'last quarter' :
                     $phase < 0.99 ? 'waxing crescent' :
                                     'new';
    my $lower_right2 = sprintf '%s moon (%3d%%)', $phase_name, $phase * 200;
    $win->addstring($maxy - 1, $maxx - length($lower_right2), $lower_right2);
}
    

sub mainloop {
    my $self = shift;

    while (1) {
        $self->draw;
        sleep(60 - time % 60);
    }
}

1;
