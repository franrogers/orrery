# orrery

Displays the positions of the sun, moon, and planets in the sky at a given location, on your terminal.

## Installation

```sh
perl Makefile.PL
make
make install
```

## Usage

```sh
# orrery LATITUDE LONGITUDE [ALTITUDE]
orrery -15.75 -69.42 3812

# LATITUDE and LONGITUDE can be decimal degrees or (-)DD:MM:SS
orrery 48:04 12:51

# ALTITUDE defaults to meters, or you can specify a unit
orrery 40:02:15 -76:06:19 436ft
```

### Display

The horizontal axis is the planets' azimuth (cardinal direction of the viewer), from 0° to 360° (i.e., facing due south) in the northern hemisphere and from -180° to 180° (i.e., facing due north) in the southern hemisphere. The vertical axis is the elevation (height in the sky), with the horizon at the center.

Planets are displayed as planetary symbols if your environment is Unicode-aware, or else as single-letter abbreviations.

### Key bindings

* `h`/`l`: go back/forward in time
* `n`: go back to the present time
* `j`/`k`: highlight next/previous planet
* `c`: clear highlight
* `?`: help
* `q`: quit

### Symbols/abbreviations
* `☉`/`S`: Sun
* `☿`/`M`: Mercury
* `♀`/`v`: Venus
* `☽`/`L`: Moon (Luna)
* `♂`/`m`: Mars
* `♃`/`j`: Jupiter
* `♄`/`s`: Saturn
* `♅`/`u`: Uranus
* `♆`/`n`: Neptune

## License
[MIT](https://choosealicense.com/licenses/mit/)
