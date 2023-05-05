// ported to Dart by Stefan Matthias Aust from a C source ported to Amiga by Rob Shimbo
import 'dart:io';
import 'dart:math';

void setRawMode(bool b) {
  stdin.echoMode = !b;
  stdin.lineMode = !b;
}

/// Returns the next character read from `stdin`. Returns `null` on EOF.
String? getchar() {
  final ch = stdin.readByteSync();
  return ch == -1 ? null : String.fromCharCode(ch);
}

/// A sector on the [board] displaying enemy presense, stars and task forces.
class Sector {
  static const right = 0;
  static const left = 1;
  static const both = 2;

  String enemy = ' ', star = ' ', tf = ' ';
}

const ENEMY = 0;
const player = 1;
const none = 2;

/// A task force of ships at a destination or on its way to a new destination.
class Tf {
  int t = 0, s = 0, c = 0, b = 0;
  int dest = 0, eta = 0, origeta = 0;
  int x = 0, y = 0, xf = 0, yf = 0;
  bool blasting = false, withdrew = false;
}

/// A star on the board. It has [Planet]s.
class Star {
  int x = 0, y = 0;
  Planet? first_planet;
  List<bool> visit = [false, false];
}

/// A planet of a [Star]. It has an owner, inhabitants, industry units, missle bases and can be conquered.
class Planet {
  int team = none;
  int number = 0, capacity = 0, psee_capacity = 0;
  int inhabitants = 0, iu = 0, mb = 0, amb = 0;
  bool conquered = false, under_attack = false;
  int esee_team = 0;
  int esee_def = 0;
  int pstar = 0;
  Planet? next;
}

/// A way to pass something by reference to a function.
class Ref<T> {
  Ref(this.value);
  T value;
}

const bdsize = 15;
const i_cost = 3;
const max_vel = 12;
const initunit = 35;
const initmoney = 30;
const mb_cost = 8;
const c_cost = 16;
const s_cost = 6;
const amb_cost = 35;
const b_cost = 70;
const c_guns = 7;
const b_guns = 40;
const s_def = 2;
const t_def = 1;
const nstars = 21;
const initvel = 1;
const initrange = 5;
const initweap = 3;
const iu_ratio = 2;
const blank_line = '                              '; // 30 spaces
const t_e_prob = 10.0;
const t_e_var = 5;
const s_e_prob = 70.0;
const s_e_var = 10;
const c_e_prob = 90.0;
const c_e_var = 10;
const b_e_prob = 97.0;
const b_e_var = 3;

final _random = Random();

/// Returns a random number between 0.0 and 1.0 (excluding).
double rand() {
  return _random.nextDouble();
}

/// Prints a formatted string with zero or more arguments to [stdout].
/// See [sprintf] for the supported subset of `%` formats.
void printf(String fmt, [Object? arg1, Object? arg2, Object? arg3]) {
  printfN(fmt, [arg1, arg2, arg3].whereType<Object>().toList());
}

/// Prints a formatted string with any number of arguments passed as a list to [stdout].
/// See [sprintf] for the supported subset of `%` formats.
void printfN(String fmt, List<Object> args) {
  stdout.write(sprintf(fmt, args));
}

/// Formats a string using [args] according to the ususal C-style `%` formats.
/// - `%%` is `%`
/// - `%c` is a character, either a 1-element string or a number
/// - `%d` is an integer number
/// - `%f` is a floating point number
/// - `%s` is a string (actually, anything coercable into a string)
/// `dfs` may be preceeded by an optional length, like `%2d` or `%-4s`.
/// `f` may also have an optional precesion value, like `%4.0f`.
String sprintf(String fmt, List<Object> args) {
  var i = 0;
  return fmt.replaceAllMapped(RegExp(r'%(%|c|-?(\d+)?(\.\d+)?[dfs])'), (match) {
    var m = match[1]!;
    if (m == '%') {
      return m;
    }
    if (m == 'c') {
      var arg = args[i++];
      if (arg is int) {
        arg = String.fromCharCode(arg);
      }
      return arg.toString();
    }
    final negate = m[0] == '-';
    final length = match[2] == null ? 0 : int.parse(match[2]!);
    final precision = match[3] == null ? -1 : int.parse(match[3]!.substring(1));
    m = m[m.length - 1];
    String s;
    if (m == 'd') {
      final arg = args[i++] as num;
      s = arg.toStringAsFixed(0);
    } else if (m == 'f') {
      final arg = args[i++] as num;
      s = precision != -1 ? arg.toStringAsFixed(precision) : arg.toString();
    } else if (m == 's') {
      s = args[i++].toString();
    } else {
      throw ArgumentError('valid %-escape');
    }
    while (s.length < length) {
      if (negate) {
        s = s + ' ';
      } else {
        s = ' ' + s;
      }
    }
    return s;
  });
}

/// Prints a single character to [stdout].
void putchar(String c) {
  stdout.write(c);
}

/// Returns the ASCII value of the given character.
int ord(String c) => c.codeUnitAt(0);

/// Returns a character for the given ASCII value.
String chr(int c) => String.fromCharCode(c);

/// Returns true if [c] is a digit.
bool isdigit(String c) => ord(c) >= ord('0') && ord(c) <= ord('9');

List<List<Sector>> board = List.generate(bdsize + 1, (_) => List.generate(bdsize + 1, (_) => Sector()));
List<List<Tf>> tf = [List.generate(27, (_) => Tf()), List.generate(27, (_) => Tf())];
List<Star> stars = List.generate(nstars + 1, (_) => Star());
List<List<int>> tf_stars = List.generate(nstars + 1, (_) => [0, 0]);
List<List<int>> col_stars = List.generate(nstars + 1, (_) => [0, 0]);
List<bool> left_line = List.filled(25, false);
List<int> range = [0, 0], vel = [0, 0], weapons = [0, 0];
late List<int> ran_req, vel_req, weap_req;
List<int> ran_working = [0, 0], vel_working = [0, 0], weap_working = [0, 0];
List<double> growth_rate = [0.0, 0.0];
List<bool> player_arrivals = List.filled(nstars + 1, false),
    enemy_arrivals = List.filled(nstars + 1, false),
    en_departures = List.filled(nstars + 1, false);
List<List<int>> r2nge = List.generate(nstars + 1, (_) => List.filled(nstars + 1, 0));
int turn = 0;
int production_year = 0;
bool game_over = false;
String en_research = '';
int x_cursor = 0, y_cursor = 0;
int bottom_field = 0;

/// Returns true, if [team] has battleships or cruisers at star [starnum].
bool any_bc(int team, int starnum) {
  bool any;
  int tf_number;
  any = false;
  if (tf_stars[starnum][team] > 0) {
    tf_number = 1;
    while ((!any) && (tf_number < 27)) {
      any = (tf[team][tf_number].dest == starnum) &&
          (tf[team][tf_number].eta == 0) &&
          ((tf[team][tf_number].c > 0) || (tf[team][tf_number].b > 0));
      tf_number = tf_number + 1;
    }
  }
  return any;
}

/// Returns the largest planet to land/conquer at star [starnum].
/// Also returns the planet's team.
int best_plan(int starnum, Ref<int> teamRef) {
  var team = none;
  var size = 0;
  var pplanet = stars[starnum].first_planet;
  while (pplanet != null) {
    if (pplanet.capacity > size) {
      size = pplanet.capacity;
      team = pplanet.team;
    }
    pplanet = pplanet.next;
  }
  teamRef.value = team;
  return size;
}

/// Checks if player or ENEMY have won, whether player has quit or 100 turns have been played.
/// End game in any of theses cases and print who has won.
void check_game_over() {
  final dead = [false, false];
  final total = [0, 0];
  final transports = [0, 0];
  final inhabs = [0, 0];
  bool quit_game;
  int tfnum, starnum;
  Planet? pplan;
  quit_game = game_over;
  for (var team = ENEMY; team <= player; team++) {
    transports[team] = 0;
    inhabs[team] = 0;
    for (tfnum = 1; tfnum <= 26; tfnum++) {
      if (tf[team][tfnum].dest != 0) {
        transports[team] = transports[team] + tf[team][tfnum].t;
      }
    }
  }
  for (starnum = 1; starnum <= nstars; starnum++) {
    pplan = stars[starnum].first_planet;
    while (pplan != null) {
      switch (pplan.team) {
        case player:
          inhabs[player] = inhabs[player] + pplan.iu;
          break;
        case ENEMY:
          inhabs[ENEMY] = inhabs[ENEMY] + pplan.iu;
          break;
      }
      pplan = pplan.next;
    }
  }
  for (var team = ENEMY; team <= player; team++) {
    total[team] = inhabs[team] + transports[team];
    dead[team] = total[team] == 0;
  }
  if ((!dead[player]) && (!dead[ENEMY]) && (turn >= 40)) {
    dead[ENEMY] = total[player] / total[ENEMY] >= 8;
    dead[player] = total[ENEMY] / total[player] >= 8;
  }
  game_over = dead[player] || dead[ENEMY] || (turn > 100) || quit_game;
  if (game_over) {
    clear_screen();
    printf('*** Game over ***\n');
    printf('Player: Population in transports:%3d', transports[player]);
    printf("  IU's on colonies: %3d  TOTAL: %3d\n", inhabs[player], total[player]);
    putchar('\n');
    printf('Enemy:  Population in transports:%3d', transports[ENEMY]);
    printf("  IU's on colonies: %3d  TOTAL: %3d\n", inhabs[ENEMY], total[ENEMY]);
    if ((total[ENEMY] > total[player]) || quit_game) {
      printf('**** THE ENEMY HAS CONQUERED THE GALAXY ***\n');
    } else if (total[player] > total[ENEMY]) {
      printf('*** PLAYER WINS- YOU HAVE SAVED THE GALAXY! ***\n');
    } else {
      printf('*** DRAWN ***\n');
    }
  }
}

bool display_forces(int ennum, int plnum, Ref<double> enoddsRef, Ref<double> ploddsRef) {
  double enodds, plodds;
  bool battle;
  int en_forces, pl_forces;
  zero_tf(ENEMY, ennum);
  zero_tf(player, plnum);
  battle = true;
  if (tf[ENEMY][ennum].dest != 0) {
    en_forces = weapons[ENEMY] * ((tf[ENEMY][ennum].c * c_guns) + (tf[ENEMY][ennum].b * b_guns));
  } else {
    en_forces = 0;
    battle = false;
  }
  if (tf[player][plnum].dest != 0) {
    pl_forces = weapons[player] * ((tf[player][plnum].c * c_guns) + (tf[player][plnum].b * b_guns));
  } else {
    pl_forces = 0;
    battle = false;
  }
  point(50, 1);
  if (tf[ENEMY][ennum].dest != 0) {
    print_star(tf[ENEMY][ennum].dest);
  } else if (tf[player][plnum].dest != 0) {
    print_star(tf[player][plnum].dest);
  }
  clear_field();
  if ((en_forces == 0) && (pl_forces == 0)) {
    battle = false;
  }
  if (battle) {
    enodds = (pl_forces.toDouble()) / (en_forces + tf[ENEMY][ennum].t * t_def + tf[ENEMY][ennum].s * s_def);
    enodds = min(14, enodds);
    enodds = exp((log(0.8)) * enodds);
    plodds = (en_forces.toDouble()) / (pl_forces + tf[player][plnum].t * t_def + tf[player][plnum].s * s_def);
    plodds = min(14, plodds);
    plodds = exp((log(0.8)) * plodds);
    point(1, 19);
    printf('enemy %5d', en_forces);
    if (en_forces > 0) {
      printf('(weap %2d)', weapons[ENEMY]);
    } else {
      printf('         ');
    }
    printf('sur: %4.0f', enodds * 100.0);
    point(1, 20);
    printf('player %5d', pl_forces);
    if (pl_forces > 0) {
      printf('(weap %2d)', weapons[player]);
    } else {
      printf('         ');
    }
    printf('sur: %4.0f', plodds * 100.0);
  } else {
    enodds = 0;
    plodds = 0;
  }
  enoddsRef.value = enodds;
  ploddsRef.value = plodds;
  return battle;
}

/// Displays the ships of the task force [taskf] at the current cursor position.
void disp_tf(Tf taskf) {
  if (taskf.t != 0) {
    printf('%2dt', taskf.t);
  } else {
    printf('   ');
  }
  if (taskf.s != 0) {
    printf('%2ds', taskf.s);
  } else {
    printf('   ');
  }
  if (taskf.c != 0) {
    printf('%2dc', taskf.c);
  } else {
    printf('   ');
  }
  if (taskf.b != 0) {
    printf('%2db', taskf.b);
  } else {
    printf('   ');
  }
}

void EN2MY_attack(int starnum) {
  int attack_factors, def_factors;
  double odds, best_score;
  Planet? pplanet, best_planet;
  int en_tf;
  final first = List.filled(8, true);
  en_tf = 1;
  while ((tf[ENEMY][en_tf].dest != starnum) || (tf[ENEMY][en_tf].eta != 0)) {
    en_tf = en_tf + 1;
  }
  do {
    attack_factors = tf[ENEMY][en_tf].c + 6 * tf[ENEMY][en_tf].b;
    best_planet = null;
    best_score = 1000.0;
    pplanet = stars[starnum].first_planet;
    while (pplanet != null) {
      if (pplanet.team == player) {
        def_factors = pplanet.esee_def;
        odds = (def_factors.toDouble()) / attack_factors;
        if (pplanet.capacity > 30) {
          odds = (odds - 2) * pplanet.capacity;
        } else {
          odds = (odds - 1.5) * pplanet.capacity;
        }
        if (odds < best_score) {
          best_score = odds;
          best_planet = pplanet;
        }
      }
      pplanet = pplanet.next;
    }
    if (best_score < 0 && best_planet != null) {
      clear_left();
      point(1, 19);
      printf('Enemy attacks: %c%d', chr(starnum + ord('A') - 1), best_planet.number);
      point(50, 1);
      print_star(starnum);
      clear_field();
      pause();
      fire_salvo(ENEMY, tf[ENEMY][en_tf], 0, best_planet, first[best_planet.number]);
      first[best_planet.number] = false;
      zero_tf(ENEMY, en_tf);
      best_planet.esee_def = best_planet.mb + 6 * best_planet.amb;
      pause();
    }
  } while (best_score < 0 && any_bc(ENEMY, starnum));
  revolt(starnum);
}

/// Returns the number of a new empty task force located at star [starnum].
/// Returns 0 if there are no task forces left.
int get_tf(int tm, int starnum) {
  int i;
  i = 1;
  while ((tf[tm][i].dest != 0) && (i < 27)) {
    i = i + 1;
  }
  if (i == 27) {
    i = 0;
  } else {
    tf[tm][i].s = 0;
    tf[tm][i].t = 0;
    tf[tm][i].c = 0;
    tf[tm][i].b = 0;
    tf[tm][i].eta = 0;
    tf[tm][i].x = stars[starnum].x;
    tf[tm][i].y = stars[starnum].y;
    tf[tm][i].xf = tf[tm][i].x;
    tf[tm][i].yf = tf[tm][i].y;
    tf[tm][i].dest = starnum;
    tf[tm][i].origeta = 0;
    tf[tm][i].blasting = false;
  }
  return i;
}

/// Adds ships of task force [child] to  [parent] and removes the it.
void joinsilent(int team, Tf parent, Tf child) {
  parent.t = parent.t + child.t;
  parent.s = parent.s + child.s;
  parent.c = parent.c + child.c;
  parent.b = parent.b + child.b;
  if ((parent.dest != 0) && (child.dest != 0)) {
    tf_stars[parent.dest][team]--;
  }
  child.dest = 0;
}

int lose(int ships, Ref<bool> lose_noneRef, String typ, Ref<double> percent) {
  var lose_none = lose_noneRef.value;
  if (ships > 0) {
    var sleft = ships;
    for (var i = 1; i <= ships; i++) {
      if (rand() > percent.value) {
        lose_none = false;
        sleft = sleft - 1;
      }
    }
    if (sleft < ships) {
      printf(' %2d%c', ships - sleft, typ);
      ships = sleft;
    }
  }
  lose_noneRef.value = lose_none;
  return ships;
}

void new_research() {
  if (weapons[player] - weapons[ENEMY] > 1) {
    en_research = 'W';
  } else {
    switch (rnd(10)) {
      case 1:
      case 2:
      case 3:
        en_research = 'V';
        break;
      case 10:
        en_research = 'R';
        break;
      default:
        en_research = 'W';
        break;
    }
  }
}

void pl2yerattack(int starnum) {
  bool battle;
  String command;
  Planet? pplanet;
  battle = any_bc(player, starnum);
  if (battle) {
    point(33, 20);
    printf('Attack at star %c', chr(starnum + ord('A') - 1));
    while (battle) {
      point(50, 1);
      print_star(starnum);
      clear_field();
      point(1, 18);
      printf('P?                            '); // 28 spaces
      point(3, 18);
      command = get_char();
      switch (command) {
        case 'S':
          starsum();
          break;
        case 'M':
          printmap();
          break;
        case 'H':
          help(3);
          pause();
          break;
        case 'N':
          make_tf();
          break;
        case 'J':
          join_tf();
          break;
        case 'C':
          print_col();
          break;
        case 'R':
          ressum();
          break;
        case 'T':
          tfsum();
          break;
        case 'G':
        case ' ':
          battle = play_salvo(starnum, battle);
          break;
        case 'B':
          printf('reak off attack');
          battle = false;
          break;
        default:
          clear_left();
          error_message();
          printf(' !Illegal command');
          break;
      }
    }
    pplanet = stars[starnum].first_planet;
    while (pplanet != null) {
      pplanet.under_attack = false;
      pplanet = pplanet.next;
    }
    point(1, 24);
    printf('Planet attack concluded       ');
    revolt(starnum);
  }
}

void tf_battle(int starnum) {
  int ennum, plnum;
  final enodds = Ref<double>(0), plodds = Ref<double>(0);
  bool battle;
  int count, new_tf, i;
  String ch;
  bool pla_loss, ene_loss;
  int size;
  int team;
  int dstar;
  final slist = List<double>.filled(nstars + 1, 0);
  bool fin, first;
  board[stars[starnum].x][stars[starnum].y].enemy = '!';
  update_board(stars[starnum].x, stars[starnum].y, Sector.left);
  ennum = 1;
  while ((tf[ENEMY][ennum].dest != starnum) || (tf[ENEMY][ennum].eta != 0)) {
    ennum = ennum + 1;
  }
  plnum = 1;
  if (tf_stars[starnum][player] > 1) {
    new_tf = get_tf(player, starnum);
    for (i = 1; i <= 26; i++) {
      if ((tf[player][i].dest == starnum) && (tf[player][i].eta == 0) && (i != new_tf)) {
        joinsilent(player, tf[player][new_tf], tf[player][i]);
      }
    }
    tf_stars[starnum][player] = 1;
    plnum = new_tf;
  } else {
    while ((tf[player][plnum].dest != starnum) || (tf[player][plnum].eta != 0)) {
      plnum = plnum + 1;
    }
  }
  battle = display_forces(ennum, plnum, enodds, plodds);
  pause();
  first = true;
  while (battle) {
    if (left_line[24]) {
      point(1, 24);
      printf(blank_line);
      left_line[24] = false;
    }
    pla_loss = true;
    ene_loss = true;
    point(1, 21);
    printf(' Enemy losses:                ');
    point(1, 22);
    printf('Player losses:                ');
    do {
      point(15, 21);
      final r1 = Ref(ene_loss);
      tf[ENEMY][ennum].t = lose(tf[ENEMY][ennum].t, r1, 't', enodds);
      tf[ENEMY][ennum].s = lose(tf[ENEMY][ennum].s, r1, 's', enodds);
      tf[ENEMY][ennum].c = lose(tf[ENEMY][ennum].c, r1, 'c', enodds);
      tf[ENEMY][ennum].b = lose(tf[ENEMY][ennum].b, r1, 'b', enodds);
      ene_loss = r1.value;
      point(15, 22);
      final r2 = Ref(pla_loss);
      tf[player][plnum].t = lose(tf[player][plnum].t, r2, 't', plodds);
      tf[player][plnum].s = lose(tf[player][plnum].s, r2, 's', plodds);
      tf[player][plnum].c = lose(tf[player][plnum].c, r2, 'c', plodds);
      tf[player][plnum].b = lose(tf[player][plnum].b, r2, 'b', plodds);
      pla_loss = r2.value;
    } while (!first && ene_loss && pla_loss);
    if (ene_loss) {
      point(15, 21);
      printf('(none)');
    }
    if (pla_loss) {
      point(15, 22);
      printf('(none)');
    }
    first = false;
    battle = display_forces(ennum, plnum, enodds, plodds);
    if (battle) {
      new_tf = get_tf(ENEMY, starnum);
      if ((tf[player][plnum].c > 0) || (tf[player][plnum].b > 0)) {
        tf[ENEMY][new_tf].t = tf[ENEMY][ennum].t;
        tf[ENEMY][new_tf].s = tf[ENEMY][ennum].s;
        final r = Ref(none);
        size = best_plan(starnum, r);
        team = r.value;
        if (((enodds.value < 0.7) && (size < 30)) ||
            ((enodds.value < 0.5) && (team == player)) ||
            ((enodds.value < 0.3) && (size < 60)) ||
            (enodds.value < 0.2)) {
          tf[ENEMY][new_tf].c = tf[ENEMY][ennum].c;
          tf[ENEMY][new_tf].b = tf[ENEMY][ennum].b;
        }
      }
      if ((tf[ENEMY][new_tf].t + tf[ENEMY][new_tf].s + tf[ENEMY][new_tf].c + tf[ENEMY][new_tf].b) > 0) {
        count = get_stars(starnum, slist);
        do {
          dstar = rnd(nstars);
        } while (slist[dstar] <= 0);
        tf[ENEMY][new_tf].dest = dstar;
        tf[ENEMY][new_tf].eta = ((slist[dstar] - 0.01) / vel[ENEMY]).truncate() + 1;
        tf[ENEMY][new_tf].xf = stars[starnum].x;
        tf[ENEMY][new_tf].yf = stars[starnum].y;
      } else {
        tf[ENEMY][new_tf].dest = 0;
      }
      fin = false;
      do {
        point(1, 18);
        printf('B?                            '); // 28 spaces
        point(3, 18);
        ch = get_char();
        switch (ch) {
          case 'M':
            printmap();
            break;
          case 'H':
            help(2);
            break;
          case 'S':
            starsum();
            break;
          case 'T':
            tfsum();
            break;
          case 'C':
            print_col();
            break;
          case '?':
            break;
          case 'R':
            ressum();
            break;
          case 'O':
            battle = display_forces(ennum, plnum, enodds, plodds);
            break;
          case 'W':
            withdraw(starnum, plnum);
            battle = display_forces(ennum, plnum, enodds, plodds);
            break;
          case ' ':
          case 'G':
            fin = true;
            break;
          default:
            printf('!illegal command');
        }
      } while (!fin && battle);
      zero_tf(ENEMY, new_tf);
      zero_tf(player, plnum);
      if (tf[ENEMY][new_tf].dest != 0) {
        point(1, 23);
        printf('en withdraws');
        point(14, 23);
        disp_tf(tf[ENEMY][new_tf]);
        tf[ENEMY][ennum].t = tf[ENEMY][ennum].t - tf[ENEMY][new_tf].t;
        tf[ENEMY][ennum].s = tf[ENEMY][ennum].s - tf[ENEMY][new_tf].s;
        tf[ENEMY][ennum].c = tf[ENEMY][ennum].c - tf[ENEMY][new_tf].c;
        tf[ENEMY][ennum].b = tf[ENEMY][ennum].b - tf[ENEMY][new_tf].b;
        zero_tf(ENEMY, ennum);
        battle = display_forces(ennum, plnum, enodds, plodds);
      }
    }
  }
  zero_tf(ENEMY, ennum);
  zero_tf(player, plnum);
  revolt(starnum);
  on_board(stars[starnum].x, stars[starnum].y);
}

void update_board(int x, int y, int option) {
  final screen_x = 3 * x + 1;
  final screen_y = 16 - y;
  switch (option) {
    case Sector.left:
      point(screen_x, screen_y);
      putchar(board[x][y].enemy);
      break;
    case Sector.right:
      point(screen_x + 2, screen_y);
      putchar(board[x][y].tf);
      break;
    case Sector.both:
      point(screen_x, screen_y);
      printf('%c%c%c', board[x][y].enemy, board[x][y].star, board[x][y].tf);
      break;
  }
}

/// Increments and prints [turn] and [production_year].
void up_year() {
  point(39, 18);
  turn = turn + 1;
  printf('Year ');
  printf('%3d', turn);
  point(48, 19);
  production_year = production_year + 1;
  printf('%d', production_year);
}

void withdraw(int starnum, int plnum) {
  int withnum;
  bool error;
  printf('ithdraw ');
  clear_left();
  point(1, 19);
  withnum = split_tf(plnum);
  if (tf[player][withnum].dest != 0) {
    point(1, 20);
    error = set_des(withnum);
    if (error) {
      tf[player][plnum].dest = starnum;
      joinsilent(player, tf[player][plnum], tf[player][withnum]);
      tf_stars[starnum][player] = 1;
    } else {
      tf[player][withnum].withdrew = true;
    }
  }
}

/// If task force [tf_num] of team [tm] has no ships, remove it.
void zero_tf(int tm, int tf_num) {
  final taskf = tf[tm][tf_num];
  if (taskf.dest != 0) {
    if ((taskf.s + taskf.t + taskf.c + taskf.b) == 0) {
      if (taskf.eta == 0) {
        tf_stars[taskf.dest][tm]--;
      }
      taskf.dest = 0;
      if (tm == player) {
        final x = taskf.x;
        final y = taskf.y;
        board[x][y].tf = ' ';
        for (var i = 1; i <= 26; i++) {
          if ((tf[player][i].dest != 0) && (tf[player][i].x == x) && (tf[player][i].y == y)) {
            if (board[x][y].tf == ' ') {
              board[x][y].tf = chr(i + ord('a') - 1);
            } else {
              board[x][y].tf = '*';
            }
          }
        }
        update_board(x, y, Sector.right);
      }
    }
  }
}

void battle() {
  bool first;
  int starnum;
  first = true;
  for (starnum = 1; starnum <= nstars; starnum++) {
    if (tf_stars[starnum][ENEMY] > 0 &&
        tf_stars[starnum][player] > 0 &&
        (any_bc(ENEMY, starnum) || any_bc(player, starnum))) {
      if (first) {
        point(33, 20);
        printf('* Tf battle *   ');
        first = false;
      }
      tf_battle(starnum);
    }
    if ((any_bc(ENEMY, starnum)) && (col_stars[starnum][player] > 0)) {
      EN2MY_attack(starnum);
    } else if ((tf_stars[starnum][player] > 0) && (col_stars[starnum][ENEMY] > 0)) {
      pl2yerattack(starnum);
    }
  }
}

void blast(Planet planet, int factors) {
  int killed;
  killed = min(planet.capacity, factors ~/ 4);
  planet.inhabitants = min(planet.inhabitants, planet.capacity) - killed;
  planet.iu = min(planet.iu - killed, planet.inhabitants * iu_ratio);
  planet.capacity = planet.capacity - killed;
  if (planet.inhabitants <= 0) {
    planet.inhabitants = 0;
    planet.iu = 0;
    planet.mb = 0;
    planet.amb = 0;
    if (planet.team != none) {
      col_stars[planet.pstar][planet.team]--;
      planet.team = none;
      planet.esee_team = none;
      planet.conquered = false;
      on_board(stars[planet.pstar].x, stars[planet.pstar].y);
    }
  }
}

void fire_salvo(int att_team, Tf task, int tfnum, Planet planet, bool first_time) {
  int bases, att_forces, def_forces;
  bool a_lose_none, p_lose_none;
  double att_odds, def_odds, attack_save, defend_save;
  int def_team;
  if (left_line[24]) {
    point(1, 24);
    printf(blank_line);
    left_line[24] = false;
  }
  if (att_team == ENEMY) {
    def_team = player;
  } else {
    def_team = ENEMY;
  }
  att_forces = weapons[att_team] * (task.c * c_guns + task.b * b_guns);
  def_forces = weapons[def_team] * (planet.mb * c_guns + planet.amb * b_guns);
  if (def_forces > 0) {
    att_odds = min(def_forces.toDouble() / att_forces, 14);
    attack_save = exp(log(0.8) * att_odds);
    def_odds = min((att_forces.toDouble()) / def_forces, 14);
    defend_save = exp(log(0.8) * def_odds);
    point(1, 20);
    if (att_team == player) {
      printf('TF%c', chr(tfnum + ord('a') - 1));
    } else {
      printf(' EN');
    }
    printf(': %4d(weap %2d)sur: %4.0f', att_forces, weapons[att_team], attack_save * 100);
    point(1, 21);
    printfN(' %c%d:%4d (weap %2d)sur: %4.0f',
        [chr(planet.pstar + ord('A') - 1), planet.number, def_forces, weapons[def_team], defend_save * 100]);
    point(1, 22);
    printf('Attacker losses:              ');
    point(1, 23);
    left_line[23] = true;
    printf(' Planet losses :              ');
    a_lose_none = true;
    p_lose_none = true;
    do {
      point(17, 22);
      final r1 = Ref(a_lose_none);
      task.c = lose(task.c, r1, 'c', Ref(attack_save));
      task.b = lose(task.b, r1, 'b', Ref(attack_save));
      a_lose_none = r1.value;
      point(17, 23);
      bases = planet.mb;
      final r2 = Ref(p_lose_none);
      planet.mb = lose(planet.mb, r2, 'm', Ref(defend_save));
      if (planet.mb != bases) {
        printf('b');
      }
      bases = planet.amb;
      planet.amb = lose(planet.amb, r2, 'a', Ref(defend_save));
      if (planet.amb != bases) {
        printf('mb');
      }
      p_lose_none = r2.value;
    } while (!first_time && p_lose_none && a_lose_none);
    if (a_lose_none) {
      point(17, 22);
      printf('(none)');
    }
    if (p_lose_none) {
      point(17, 23);
      printf('(none)');
    }
  }
  if ((planet.mb + planet.amb == 0) && (any_bc(att_team, planet.pstar))) {
    point(1, 24);
    printf('Planet %d falls!               ', planet.number);
    planet.team = att_team;
    planet.esee_team = att_team;
    planet.conquered = true;
    col_stars[task.dest][def_team]--;
    col_stars[task.dest][att_team]++;
    point(50, 1);
    print_star(planet.pstar);
    clear_field();
    on_board(stars[task.dest].x, stars[task.dest].y);
  }
}

bool play_salvo(int starnum, bool battle) {
  String tf_char, planch;
  int planet_num, tf_num;
  bool found;
  Planet pplanet;
  bool first_time;
  printf('Attack planet ');
  pplanet = stars[starnum].first_planet!;
  if (col_stars[starnum][ENEMY] > 1) {
    printf(':');
    planch = get_char();
    clear_left();
    planet_num = ord(planch) - ord('0');
    found = false;
    while (!found) {
      if (pplanet.number == planet_num) {
        found = true;
      } else if (pplanet.next == null) {
        found = true;
      } else {
        pplanet = pplanet.next!;
      }
    }
    if (pplanet.number != planet_num) {
      planet_num = 0;
      error_message();
      printf('! That is not a useable planet');
    } else if (pplanet.team != ENEMY) {
      error_message();
      printf(' !Not an enemy colony');
      planet_num = 0;
    }
  } else {
    planet_num = 1;
    while (pplanet.team != ENEMY) {
      pplanet = pplanet.next!;
    }
    printf('%d', pplanet.number);
    clear_left();
  }
  if (planet_num != 0) {
    point(1, 19);
    printf(' attacking tf ');
    if (tf_stars[starnum][player] > 1) {
      printf(':');
      tf_char = get_char();
      tf_num = ord(tf_char) - ord('A') + 1;
    } else {
      tf_num = 1;
      while (tf[player][tf_num].dest != starnum || tf[player][tf_num].eta != 0) {
        tf_num++;
      }
      putchar(chr(tf_num + ord('a') - 1));
    }
    if (tf_num < 1 || tf_num > 26) {
      error_message();
      printf(' !Illegal tf');
    } else if (tf[player][tf_num].dest == 0) {
      error_message();
      printf(' !Nonexistent tf');
    } else if ((tf[player][tf_num].dest != starnum) || (tf[player][tf_num].eta != 0)) {
      error_message();
      printf(' !Tf is not at this star');
    } else if ((tf[player][tf_num].b + tf[player][tf_num].c) == 0) {
      error_message();
      printf(' !Tf has no warships');
    } else {
      first_time = !pplanet.under_attack;
      if (!pplanet.under_attack) {
        pplanet.under_attack = true;
        point(50, 1);
        print_star(starnum);
        clear_field();
      }
      fire_salvo(player, tf[player][tf_num], tf_num, pplanet, first_time);
      zero_tf(player, tf_num);
      battle = (col_stars[starnum][ENEMY] > 0) && (any_bc(player, starnum));
    }
  }
  return battle;
}

void print_planet(Planet pplanet, bool see) {
  printf('%d:%2d                         ', pplanet.number, pplanet.psee_capacity);
  point(x_cursor + 5, y_cursor);
  x_cursor = x_cursor - 5;
  if (pplanet.psee_capacity == 0) {
    printf(' Decimated');
  } else if ((pplanet.team == none) && see) {
    printf(' No colony');
  } else if (pplanet.team == player) {
    printf('(%2d,/%3d)', pplanet.inhabitants, pplanet.iu);
    if (pplanet.conquered) {
      printf('Con');
    } else {
      printf('   ');
    }
    if (pplanet.mb != 0) {
      printf('%2dmb', pplanet.mb);
    } else {
      printf('    ');
    }
    if (pplanet.amb != 0) {
      printf('%2damb', pplanet.amb);
    }
  } else if ((pplanet.team == ENEMY) && see) {
    printf('*EN*');
    if (pplanet.conquered) {
      printf('Con');
    } else {
      printf('   ');
    }
    if (pplanet.under_attack) {
      if (pplanet.mb != 0) {
        printf('%2dmb', pplanet.mb);
      } else {
        printf('    ');
      }
      if (pplanet.amb != 0) {
        printf('%2damb', pplanet.amb);
      }
    }
  }
  point(x_cursor, y_cursor + 1);
}

void print_col() {
  bool see;
  Planet? pplanet;
  printf('olonies:');
  point(50, 1);
  for (var i = 1; i <= nstars; i++) {
    pplanet = stars[i].first_planet;
    while (pplanet != null) {
      if ((pplanet.team) == player) {
        putchar(chr(i + ord('A') - 1));
        see = true;
        if (((y_cursor > 21) && (x_cursor >= 50)) || (y_cursor > 24)) {
          pause();
          clear_field();
          point(50, 1);
        }
        print_planet(pplanet, see);
      }
      pplanet = pplanet.next;
    }
  }
  clear_field();
  clear_left();
}

void starsum() {
  Line iline;
  int i;
  String strs;
  printf('tar summary:');
  clear_left();
  point(1, 19);
  putchar(':');
  iline = get_line(true);
  strs = get_token(iline);
  point(50, 1);
  if (strs == ' ') {
    for (i = 1; i <= nstars; i++) {
      print_star(i);
    }
  } else {
    do {
      i = ord(strs) - ord('A') + 1;
      print_star(i);
      strs = get_token(iline);
    } while (strs != ' ');
  }
  clear_field();
}

void tfsum() {
  int i;
  String tfs;
  Line iline;
  printf('f summary :');
  iline = get_line(true);
  tfs = get_token(iline);
  point(50, 1);
  if (tfs == ' ') {
    for (i = 1; i <= 26; i++) {
      print_tf(i);
    }
  } else {
    do {
      i = ord(tfs) - ord('A') + 1;
      print_tf(i);
      tfs = get_token(iline);
    } while (tfs != ' ');
  }
  clear_field();
  clear_left();
}

void revolt(int starnum) {
  Planet? pplan;
  int loses, gets_back;
  pplan = stars[starnum].first_planet;
  if (col_stars[starnum][ENEMY] + col_stars[starnum][player] > 0) {
    while (pplan != null) {
      if (pplan.conquered) {
        if ((pplan.team == player) && (!any_bc(player, starnum))) {
          loses = player;
          gets_back = ENEMY;
        } else if ((pplan.team == ENEMY) && (!any_bc(ENEMY, starnum))) {
          loses = ENEMY;
          gets_back = player;
        } else {
          loses = none;
          gets_back = none;
        }
        if (loses != none) {
          col_stars[starnum][loses] = col_stars[starnum][loses] - 1;
          col_stars[starnum][gets_back]++;
          pplan.team = gets_back;
          pplan.conquered = false;
          pplan.psee_capacity = pplan.capacity;
          on_board(stars[starnum].x, stars[starnum].y);
        }
      }
      pplan = pplan.next;
    }
  }
}

/// Creates a random number of planets at [ustar].
/// Distribution is 0, 1, 1, 2.
void assign_planets(Star ustar, int starnum) {
  int i1, nplanets;
  Planet pplanet;
  nplanets = rnd(4) - 2;
  if (nplanets < 0) {
    nplanets = 1;
  }
  if (nplanets == 0) {
    ustar.first_planet = null;
  } else {
    pplanet = Planet();
    ustar.first_planet = pplanet;
    for (i1 = 1; i1 <= nplanets; i1++) {
      pplanet.number = rnd(2) + (2 * i1) - 2;
      if (rnd(4) > 2) {
        pplanet.capacity = 10 * (rnd(4) + 2);
      } else {
        pplanet.capacity = 5 * rnd(3);
      }
      pplanet.psee_capacity = pplanet.capacity;
      pplanet.team = none;
      pplanet.inhabitants = 0;
      pplanet.iu = 0;
      pplanet.mb = 0;
      pplanet.amb = 0;
      pplanet.conquered = false;
      pplanet.under_attack = false;
      pplanet.esee_team = none;
      pplanet.esee_def = 1;
      pplanet.pstar = starnum;
      if (i1 == nplanets) {
        pplanet.next = null;
      } else {
        pplanet.next = Planet();
        pplanet = pplanet.next!;
      }
    }
  }
}

/// Initializes the game, especially the player.
void initconst() {
  int i3, i1, i2, x, y, temp;
  int team;

  printf('\n* Welcome to CONQUEST! *\n\n');
  printf('Dart version 1.0\n');
  printf('Hit return to continue\n');
  get_char();

  // setup the board
  for (i1 = 1; i1 <= bdsize; i1++) {
    for (i2 = 1; i2 <= bdsize; i2++) {
      board[i1][i2].enemy = ' ';
      board[i1][i2].tf = ' ';
      board[i1][i2].star = '.';
    }
  }

  // setup and distribute the stars
  for (i1 = 1; i1 <= nstars; i1++) {
    enemy_arrivals[i1] = false;
    en_departures[i1] = false;
    player_arrivals[i1] = false;

    for (team = ENEMY; team <= player; team++) {
      tf_stars[i1][team] = 0;
      col_stars[i1][team] = 0;
    }

    do {
      x = rnd(bdsize);
      y = rnd(bdsize);
    } while (board[x][y].star != '.');
    stars[i1].x = x;
    stars[i1].y = y;

    for (i2 = 1; i2 <= i1; i2++) {
      if (i1 == i2) {
        r2nge[i1][i2] = 0;
      } else {
        temp = ((x - stars[i2].x) * (x - stars[i2].x)) + ((y - stars[i2].y) * (y - stars[i2].y));
        r2nge[i1][i2] = 23;
        for (i3 = 1; i3 < 22; i3++) {
          if (temp < i3 * i3) {
            r2nge[i1][i2] = i3;
            break;
          }
        }
        r2nge[i2][i1] = r2nge[i1][i2];
      }
    }

    board[x][y].star = chr(ord('A') + i1 - 1);
    board[x][y].enemy = '?';

    assign_planets(stars[i1], i1);
  }

  ran_req = [0, 0, 0, 0, 0, 0, 20, 40, 70, 100, 150, 200, 300, 400, 600, 900];
  vel_req = [0, 0, 40, 60, 80, 120, 150, 200, 250, 300, 400, 500, 600];
  weap_req = [0, 0, 0, 0, 50, 70, 90, 120, 150, 250, 350];

  for (team = ENEMY; team <= player; team++) {
    for (i1 = 1; i1 <= 26; i1++) {
      tf[team][i1].dest = 0;
      tf[team][i1].blasting = false;
      tf[team][i1].withdrew = false;
      tf[team][i1].s = 0;
      tf[team][i1].t = 0;
      tf[team][i1].c = 0;
      tf[team][i1].b = 0;
      tf[team][i1].dest = 0;
      tf[team][i1].eta = 0;
    }
    tf[team][1].t = initunit;
    vel[team] = initvel;
    range[team] = initrange;
    weapons[team] = initweap;
    weap_working[team] = 0;
    vel_working[team] = 0;
    ran_working[team] = 0;
  }

  growth_rate[player] = 0.3;
  growth_rate[ENEMY] = 0.5;

  game_over = false;
  turn = 1;
  production_year = 1;

  printmap();
  point(33, 20);
  printf('*Initialization*');
  init_player();
}

void init_player() {
  String str, key;
  int star_number;
  int balance, cost, amt;
  Line iline;
  do {
    point(1, 18);
    printf('start at star?\n     ');
    str = get_char();
    point(1, 19);
    star_number = ord(str) - ord('A') + 1;
  } while (star_number < 1 || star_number > nstars);
  tf[player][1].x = stars[star_number].x;
  tf[player][1].y = stars[star_number].y;
  tf_stars[star_number][player] = 1;
  tf[player][1].dest = star_number;
  point(1, 20);
  printf('choose your initial fleet.');
  point(1, 21);
  printf('you have %d transports', initunit);
  point(1, 22);
  printf(' && %d units to spend', initmoney);
  point(1, 23);
  printf('on ships or research.');
  balance = initmoney;
  do {
    point(1, 19);
    print_tf(1);
    point(1, 18);
    printf('%3d?                          ', balance);
    point(6, 18);
    iline = get_line(false);
    do {
      key = get_token(iline);
      amt = iline.amount;
      switch (key) {
        case 'C':
          cost = amt * c_cost;
          if (cost <= balance) {
            tf[player][1].c = tf[player][1].c + amt;
          }
          break;
        case 'S':
          cost = amt * s_cost;
          if (cost <= balance) {
            tf[player][1].s = tf[player][1].s + amt;
          }
          break;
        case 'B':
          cost = amt * b_cost;
          if (cost <= balance) {
            tf[player][1].b = tf[player][1].b + amt;
          }
          break;
        case 'H':
          help(0);
          cost = 0;
          break;
        case 'W':
        case 'V':
        case 'R':
          cost = amt;
          if (cost <= balance) {
            research(player, key, amt);
          }
          break;
        case ' ':
          cost = 0;
          break;
        case '>':
          point(1, 18);
          printf('>?      ');
          point(3, 18);
          cost = 0;
          key = get_char();
          switch (key) {
            case 'M':
              printmap();
              break;
            case 'R':
              ressum();
              break;
            default:
              error_message();
              printf(' !Only M,R during initialize');
          }
          break;
        default:
          cost = 0;
          error_message();
          printf(' !Illegal field %c', key);
      }
      if (cost <= balance) {
        balance = balance - cost;
      } else {
        cost = 0;
        error_message();
        printf("  !can't afford %c", key);
      }
    } while (key != ' ');
  } while (balance > 0);
  stars[star_number].visit[player] = true;
  board[stars[star_number].x][stars[star_number].y].tf = 'a';
  board[stars[star_number].x][stars[star_number].y].enemy = ' ';
  on_board(stars[star_number].x, stars[star_number].y);
  point(33, 20);
}

/// Initializes the enemy.
void initmach() {
  int res_amt, maxx, start_star, starnum, count;
  final slist = List<double>.filled(nstars + 1, 0);

  range[ENEMY] = initrange + 2;

  switch (rnd(3)) {
    case 1:
      weapons[ENEMY] = rnd(4) + 2;
      break;
    case 2:
      vel[ENEMY] = rnd(3);
      break;
    case 3:
      growth_rate[ENEMY] = (rnd(4) + 3) / 10.0;
      break;
  }

  // enemy buys 1 cruiser, 2 scouts and 2 points velocity research
  tf[ENEMY][1].c = 1;
  tf[ENEMY][1].s = 2;

  res_amt = 2;
  en_research = 'V';
  research(ENEMY, en_research, res_amt);

  // find a star which has the most (give or take 5) stars in reach
  maxx = 0;
  start_star = 0;
  for (starnum = 1; starnum <= nstars; starnum++) {
    count = get_stars(starnum, slist);
    count += rnd(5);
    if (count > maxx) {
      maxx = count;
      start_star = starnum;
    }
  }

  // put enemy's  to that star (too bad if the player is here, too)
  tf[ENEMY][1].dest = start_star;
  tf[ENEMY][1].x = stars[start_star].x;
  tf[ENEMY][1].y = stars[start_star].y;
  stars[start_star].visit[ENEMY] = true;
  tf_stars[start_star][ENEMY] = 1;

  // immediately start a battle if enemy and player happen to start at the same star
  point(50, 1);
  print_star(tf[player][1].dest);
  clear_field();
  if (start_star == tf[player][1].dest) {
    clear_left();
    battle();
  }
}

/// Moves the cursor to the given position.
/// Remembers position in [x_cursor] and [y_cursor].
/// Marks [left_line] for lines 1 to 17 and 19.
void point(int col, int row) {
  printf('\x1B[%d;%dH', row, col);
  x_cursor = col;
  y_cursor = row;
  if (x_cursor < 20 && y_cursor != 18) {
    left_line[y_cursor] = true;
  }
}

/// Returns a random integer between 1 and [n].
int rnd(int n) {
  return (rand() * n).truncate() + 1;
}

/// Rounds [x] to the nearest integer.
int round(double x) {
  if (x < 0.0) {
    return (x - 0.5).truncate();
  } else {
    return (x + 0.5).truncate();
  }
}

/// Marks [en_departures] for the given star if the player has s or colonies at this star.
void depart(int starnum) {
  if (tf_stars[starnum][player] + col_stars[starnum][player] > 0) {
    en_departures[starnum] = true;
  }
}

/// Rates the [planet] whether it is worth visiting, attacking or colonizing.
/// Returns 1..120 for uncolonized planets.
/// Returns 201..320 for underdefended enemy planets.
/// Returns 301..420 for enemy planets conquered by the player.
/// Returns 601..620 for unknown planets.
/// Returns 1001..1020 for player planets conquered by the enemy.
/// The rate is reduced by 250 if the planet if heavily defended.
int eval_bc_col(Planet planet) {
  int result;
  if (!stars[planet.pstar].visit[ENEMY]) {
    result = 600;
  } else {
    switch (planet.esee_team) {
      case none:
        result = 100;
        break;
      case ENEMY:
        if (planet.conquered) {
          result = 1000;
        } else if ((6 * planet.amb + planet.mb <= planet.iu / 15) && (!(!planet.conquered && planet.iu < mb_cost))) {
          result = 300;
        } else {
          result = 0;
        }
        if (planet.amb >= 4) {
          result -= 250;
        }
        break;
      case player:
        if (planet.conquered) {
          result = 400;
        } else {
          result = 200;
        }
        break;
      default:
        throw Error();
    }
    if (planet.capacity < 40 && planet.iu < 15) {
      result -= 100;
    }
  }
  return result + rnd(20);
}

int eval_t_col(Planet planet, double range) {
  int result;
  if (!stars[planet.pstar].visit[ENEMY]) {
    result = 60;
  } else {
    switch (planet.esee_team) {
      case none:
        result = 40;
        break;
      case ENEMY:
        result = 30;
        break;
      case player:
        result = 0;
        break;
      default:
        throw Error();
    }
    if (planet.esee_team != player && planet.capacity - planet.inhabitants > 40 - (turn / 2)) {
      result += 40;
    }
  }
  return result - (2 * range + 0.5).truncate();
}

/// Generates enemy moves.
/// Sends scouts to explore stars.
/// Sends transports to colonize planets.
/// Sends cruisers and battleships to conquer.
/// Removes empty s.
void inputmach() {
  int count, tfnum, starnum;
  final slist = List<double>.filled(nstars + 1, 0);
  for (tfnum = 1; tfnum <= 26; tfnum++) {
    if ((tf[ENEMY][tfnum].eta == 0) && (tf[ENEMY][tfnum].dest != 0)) {
      starnum = tf[ENEMY][tfnum].dest;
      count = get_stars(starnum, slist);
      send_scouts(slist, tf[ENEMY][tfnum]);
      send_transports(slist, tf[ENEMY][tfnum]);
      move_bc(tf[ENEMY][tfnum], slist);
      zero_tf(ENEMY, tfnum);
    }
  }
}

void move_bc(Tf task, List<double> slist) {
  int best_star, top_score, starnum, score, factors;
  Planet? pplanet, best_planet;
  if (task.b > 0 || task.c > 0) {
    // task force has cruisers and/or battleships
    for (starnum = 1; starnum <= nstars; starnum++) {
      // find any reachable star
      if (slist[starnum] > 0) {
        best_star = starnum;
        break;
      }
    }
    best_star = -1;
    best_planet = null;
    top_score = -1000;
    for (starnum = 1; starnum <= nstars; starnum++) {
      if (slist[starnum] > 0 || starnum == task.dest) {
        pplanet = stars[starnum].first_planet;
        while (pplanet != null) {
          score = eval_bc_col(pplanet);
          if (starnum == task.dest) {
            score += 250;
          }
          if (tf_stars[starnum][ENEMY] > 0) {
            score -= 150;
          }
          if (score > top_score) {
            top_score = score;
            best_planet = pplanet;
            best_star = starnum;
          }
          pplanet = pplanet.next;
        }
      }
    }
    if (best_star == task.dest) {
      if (best_planet != null) {
        if ((best_planet.team == ENEMY) && (best_planet.conquered) && (best_planet.iu < 20)) {
          factors = weapons[ENEMY] * ((task.c * c_guns) + (task.b * b_guns));
          factors = min(factors, 4 * best_planet.inhabitants);
          blast(best_planet, factors);
          if ((tf_stars[best_planet.pstar][player] > 0) || (col_stars[best_planet.pstar][player] > 0)) {
            best_planet.psee_capacity = best_planet.capacity;
          }
        } else if ((best_planet.team == ENEMY) && (best_planet.conquered)) {
          if ((((task.b > 3) || (task.c > 3)) && (rnd(4) == 4)) || (task.b > 8)) {
            wander_bc(task, slist);
          }
        }
      }
    } else {
      tf_stars[task.dest][ENEMY]--;
      depart(task.dest);
      task.dest = best_star;
      task.eta = ((slist[best_star] - 0.01) / vel[ENEMY]).truncate() + 1;
    }
  }
}

/// Sends all transports of task force [task] to interesting stars or land them.
void send_transports(List<double> slist, Tf task) {
  int new_tf, to_land, sec_star, sec_score, best_star, top_score, score, starnum;
  int xstar;
  Planet? pplan, best_plan;
  int trash1, trash2;

  if (task.t > 0) {
    // task force has transports
    best_star = 0;
    sec_star = 0;
    sec_score = -11000;
    top_score = -10000;
    best_plan = null;
    for (starnum = 1; starnum <= nstars; starnum++) {
      if (slist[starnum] > 0 || starnum == task.dest) {
        // search reachable stars
        pplan = stars[starnum].first_planet;
        while (pplan != null) {
          score = eval_t_col(pplan, slist[starnum]);
          xstar = starnum;
          if (score > top_score) {
            int t;
            t = best_star;
            best_star = xstar;
            xstar = t;
            t = top_score;
            top_score = score;
            score = t;
            best_plan = pplan;
          }
          if (score > sec_score) {
            sec_score = score;
            sec_star = xstar;
          }
          pplan = pplan.next;
        }
      }
    }
    if (best_star == task.dest && best_plan != null) {
      // no reachable star is better than the current star
      if (tf_stars[best_star][player] == 0 && best_plan.team != player) {
        trash1 = task.t;
        trash2 = ((best_plan.capacity - best_plan.inhabitants) / 3).truncate();
        to_land = min(trash1, trash2);
        if (to_land > 0) {
          // land transports
          if (best_plan.inhabitants == 0) {
            // a new colony is founded
            best_plan.team = ENEMY;
            best_plan.esee_team = ENEMY;
            col_stars[best_star][ENEMY] += 1;
          }
          best_plan.inhabitants += to_land;
          best_plan.iu += to_land;
          task.t -= to_land;
          send_transports(slist, task);
        }
      }
    } else {
      if (task.t >= 10 && sec_star > 0) {
        // more than 10 transport are split if there's a second candidate
        new_tf = get_tf(ENEMY, task.dest);
        tf[ENEMY][new_tf].t = (task.t / 2).truncate();
        task.t -= tf[ENEMY][new_tf].t;
        if (task.c > 0 && !underdefended(task.dest)) {
          // we can affort some escort
          tf[ENEMY][new_tf].c = 1;
          task.c -= 1;
        }
        send_t_tf(tf[ENEMY][new_tf], slist, best_star);
        best_star = sec_star;
      }
      new_tf = get_tf(ENEMY, task.dest);
      tf[ENEMY][new_tf].t = task.t;
      task.t = 0;
      if (task.c > 0 && !underdefended(task.dest)) {
        // we can affort some escort
        tf[ENEMY][new_tf].c = 1;
        task.c -= 1;
      }
      send_t_tf(tf[ENEMY][new_tf], slist, best_star);
    }
  }
}

void send_t_tf(Tf task, List<double> slist, int dest_star) {
  depart(task.dest);
  task.dest = dest_star;
  task.eta = ((slist[dest_star] - 0.01) / vel[ENEMY]).truncate() + 1;
}

/// Sends all scouts of task force [task] to unexplored stars.
void send_scouts(List<double> slist, Tf task) {
  int dest, new_tf, j, doind;
  final doable = List.filled(nstars + 1, 0);

  if (task.s > 0) {
    // task force has scouts
    doind = 0;
    for (j = 1; j <= nstars; j++) {
      if (!stars[j].visit[ENEMY] && slist[j] > 0) {
        // an unexplored star is reachable
        doable[++doind] = j;
      }
    }
    while (doind > 0 && task.s > 0) {
      // as long as we have scouts and stars...
      new_tf = get_tf(ENEMY, task.dest);
      tf[ENEMY][new_tf].s = 1;
      dest = rnd(doind);
      tf[ENEMY][new_tf].dest = doable[dest];
      tf[ENEMY][new_tf].eta = ((slist[doable[dest]] - 0.01) / vel[ENEMY]).truncate() + 1;
      depart(task.dest);
      doable[dest] = doable[doind];
      doind -= 1;
      task.s -= 1;
    }
    while (task.s > 0) {
      // as long as there are still scouts pick a random unreachable star...
      do {
        dest = rnd(nstars);
      } while (slist[dest] <= 0);
      new_tf = get_tf(ENEMY, task.dest);
      tf[ENEMY][new_tf].s = 1;
      tf[ENEMY][new_tf].dest = dest;
      tf[ENEMY][new_tf].eta = ((slist[dest] - 0.01) / vel[ENEMY]).truncate() + 1;
      depart(task.dest);
      task.s -= 1;
    }
  }
}

bool underdefended(int starnum) {
  Planet? pplanet;
  bool result;
  result = false;
  pplanet = stars[starnum].first_planet;
  while (pplanet != null && !result) {
    if ((pplanet.team == ENEMY) && (pplanet.iu > 10) && ((6 * pplanet.amb + pplanet.mb) < round(pplanet.iu / 15))) {
      result = true;
    }
    pplanet = pplanet.next;
  }
  return result;
}

void wander_bc(Tf task, List<double> slist) {
  int ships, i, count, dest, new_tf;
  if ((task.b > 1) || (task.c > 1)) {
    count = 0;
    for (i = 1; i <= nstars; i++) {
      if (slist[i] != 0) {
        count = count + 1;
      }
    }
    if (count > 0) {
      dest = rnd(count);
      count = 0;
      i = 0;
      do {
        i = i + 1;
        if (slist[i] > 0) {
          count = count + 1;
        }
      } while (count != dest);
      new_tf = get_tf(ENEMY, task.dest);
      ships = (task.b / 2).floor();
      tf[ENEMY][new_tf].b = ships;
      task.b = task.b - ships;
      ships = (task.c / 2).floor();
      tf[ENEMY][new_tf].c = ships;
      task.c = task.c - ships;
      if (task.t > 3) {
        tf[ENEMY][new_tf].t = 2;
        task.t = task.t - 2;
      }
      tf[ENEMY][new_tf].dest = i;
      tf[ENEMY][new_tf].eta = ((slist[i] - 0.01) / vel[ENEMY]).truncate() + 1;
      depart(task.dest);
    }
  }
}

void move_ships() {
  double ratio, prob;
  int there, dx, dy;
  int tm;
  Planet? pplanet;
  bool any, loss;
  /*clear the board*/
  for (var i = 1; i <= 26; i++) {
    if ((tf[player][i].dest != 0) && (tf[player][i].eta != 0)) {
      board[tf[player][i].x][tf[player][i].y].tf = ' ';
      update_board(tf[player][i].x, tf[player][i].y, Sector.right);
    }
  }
  /*move ships of both teams*/
  tm = ENEMY;
  do {
    for (var i = 1; i <= 26; i++) {
      final t = tf[tm][i];
      if (t.dest != 0 && t.eta != 0) {
        // tf is moving
        t.eta = t.eta - 1;
        final arrived = t.eta == 0;

        if (!stars[t.dest].visit[tm] && arrived && tm == player) {
          // player tf is arriving at unexplored star
          left_line[20] = true;
          clear_left();
          point(1, 19);
          printf('Task force %c exploring %c.\n', chr(i + ord('a') - 1), chr(t.dest + ord('@')));

          prob = (t_e_prob + rnd(t_e_var) * t.t) / 100.0;
          if (t.s != 0) prob = (s_e_prob + rnd(s_e_var) * t.s) / 100.0;
          if (t.c != 0) prob = (c_e_prob + rnd(c_e_var) * t.c) / 100.0;
          if (t.b != 0) prob = (b_e_prob + rnd(b_e_var) * t.b) / 100.0;
          prob = min(prob, 100);

          final rloss = Ref(true);
          final rprob = Ref(prob);
          t.t = lose(t.t, rloss, 't', rprob);
          t.s = lose(t.s, rloss, 's', rprob);
          t.c = lose(t.c, rloss, 'c', rprob);
          t.b = lose(t.b, rloss, 'b', rprob);
          loss = rloss.value;

          if (loss) {
            printf('No ships');
          }
          printf(' destroyed.');
          left_line[23] = true;
          pause();

          t.eta = 1;
          zero_tf(tm, i);
          t.eta = 0;
        }

        if (t.dest != 0) {
          // tf wasn't destroyed
          if (tm == player) {
            dx = stars[t.dest].x;
            dy = stars[t.dest].y;
            ratio = 1.0 - t.eta.toDouble() / t.origeta;
            t.x = t.xf + round(ratio * (dx - t.xf));
            t.y = t.yf + round(ratio * (dy - t.yf));

            if (arrived) {
              // player tf has reached destination star
              pplanet = stars[t.dest].first_planet;
              while (pplanet != null) {
                pplanet.psee_capacity = pplanet.capacity;
                pplanet = pplanet.next;
              }
              player_arrivals[t.dest] = true;
              if (!stars[t.dest].visit[tm]) {
                board[t.x][t.y].enemy = ' ';
                update_board(t.x, t.y, Sector.left);
                stars[t.dest].visit[tm] = true;
              }
            }
          }
          if (tm == ENEMY && arrived) {
            // enemy tf has reached destination star
            pplanet = stars[t.dest].first_planet;
            stars[t.dest].visit[tm] = true;
            while (pplanet != null) {
              pplanet.esee_team = pplanet.team;
              pplanet = pplanet.next;
            }
            if (tf_stars[t.dest][tm] > 0) {
              // there are already other enemy tfs present
              there = 1;
              while (there == i || tf[tm][there].dest != t.dest || tf[tm][there].eta != 0) {
                there = there + 1;
              }
              joinsilent(tm, t, tf[tm][there]);
            }
            if (tf_stars[t.dest][player] > 0 || col_stars[t.dest][player] > 0) {
              // player has tf or cols at enemy's destination star so he notices the fleet
              enemy_arrivals[t.dest] = true;
            }
          }
          if (t.eta == 0) {
            tf_stars[t.dest][tm]++;
          }
        }
      }
    }
    tm++;
  } while (tm != none);
  /* put the good guys on the board*/
  for (var i = 1; i <= 26; i++) {
    if (tf[player][i].dest != 0) {
      tf[player][i].blasting = false;
      dx = tf[player][i].x;
      dy = tf[player][i].y;
      if (board[dx][dy].tf == ' ') {
        board[dx][dy].tf = chr(i + ord('a') - 1);
      } else if (board[dx][dy].tf != chr(i + ord('a') - 1)) {
        board[dx][dy].tf = '*';
      }
      update_board(dx, dy, Sector.right);
    }
  }
  any = false;
  for (var i = 1; i <= nstars; i++) {
    if (player_arrivals[i]) {
      if (!any) {
        point(33, 21);
        printf('Player arrivals :   ');
        point(50, 21);
        any = true;
      }
      putchar(chr(i + ord('A') - 1));
      player_arrivals[i] = false;
    }
  }
  if ((!any) && (true)) {
    point(33, 21);
    printf(blank_line);
  }
  any = false;
  for (var i = 1; i <= nstars; i++) {
    if (enemy_arrivals[i]) {
      if (!any) {
        point(33, 22);
        printf('Enemy arrivals  :   ');
        point(50, 22);
        any = true;
      }
      putchar(chr(i + ord('A') - 1));
      enemy_arrivals[i] = false;
    }
  }
  if ((!any) && (true)) {
    point(33, 22);
    printf(blank_line);
  }
  any = false;
  for (var i = 1; i <= nstars; i++) {
    if (en_departures[i]) {
      if (!any) {
        point(33, 23);
        printf('Enemy departures:   ');
        point(50, 23);
        any = true;
      }
      putchar(chr(i + ord('A') - 1));
      en_departures[i] = false;
    }
  }
  if ((!any) && (true)) {
    point(33, 23);
    printf(blank_line);
  }
  for (var i = 1; i <= nstars; i++) {
    revolt(i);
  }
}

/// Clears the screen and displays the [board], [turn] and [production_year].
void printmap() {
  int i1, i2;
  clear_screen();
  for (i1 = bdsize; i1 >= 1; i1--) {
    if ((i1 == 1) || (((i1 / 5) * 5) == i1)) {
      printf('%2d|', i1);
    } else {
      printf('  |');
    }
    for (i2 = 1; i2 <= bdsize; i2++) {
      printf('%c%c%c', board[i2][i1].enemy, board[i2][i1].star, board[i2][i1].tf);
    }
    printf('|\n');
  }
  printf('   ');
  for (i1 = 1; i1 <= bdsize; i1++) {
    printf('---');
  }
  putchar('\n');
  printf('   ');
  for (i1 = 1; i1 <= bdsize; i1++) {
    if ((i1 == 1) || (((i1 / 5) * 5) == i1)) {
      printf('%2d ', i1);
    } else {
      printf('   ');
    }
  }
  putchar('\n');
  point(33, 18);
  printf('Turn: %3d', turn);
  point(33, 19);
  printf('Production yr: %d', production_year);
  bottom_field = 0;
  for (i1 = 19; i1 <= 24; i1++) {
    left_line[i1] = false;
  }
}

void blast_planet() {
  String tf_char, pl_char;
  int tf_num, planet_num;
  Planet? pplanet;
  int factors, starnum;
  bool see, done;
  Line iline;
  int amount;
  String dum;

  printf('last');
  clear_left();
  point(1, 19);
  printf('Firing TF:');
  tf_char = get_char();
  tf_num = ord(tf_char) - ord('A') + 1;
  if (tf_num < 1 || tf_num > 26) {
    error_message();
    printf(' !Illegal tf');
  } else if (tf[player][tf_num].dest == 0) {
    error_message();
    printf(' !Nonexistent tf');
  } else if (tf[player][tf_num].eta != 0) {
    error_message();
    printf(' !Tf is not in normal space  ');
  } else if (tf[player][tf_num].blasting) {
    error_message();
    printf(' !Tf is already blasting     ');
  } else if ((tf[player][tf_num].b == 0) && (tf[player][tf_num].c == 0)) {
    error_message();
    printf(' !Tf has no warships         ');
  } else {
    starnum = tf[player][tf_num].dest;
    pplanet = stars[starnum].first_planet;
    if (pplanet == null) {
      error_message();
      printf(' !No planets at star %c       ', chr(starnum + ord('A') - 1));
    } else {
      point(1, 20);
      printf('Target colony ');
      if (pplanet.next == null) {
        printf('%2d', pplanet.number);
      } else {
        printf(':');
        pl_char = get_char();
        planet_num = ord(pl_char) - ord('0');
        done = false;
        while (!done) {
          if (pplanet!.number == planet_num) {
            done = true;
            // a simple `==` triggers a false positive linter warning
          } else if (!(pplanet.next != null)) {
            done = true;
          } else {
            pplanet = pplanet.next;
          }
        }
        if (pplanet!.number != planet_num) {
          error_message();
          printf(' !No such planet at this star ');
          pplanet = null;
        }
      }
      if (pplanet != null) {
        if (pplanet.team == ENEMY) {
          error_message();
          printf(' !Conquer it first!');
        } else if ((pplanet.team == player) && (!pplanet.conquered)) {
          error_message();
          printf(' !That is a human colony!!    ');
        } else {
          factors = weapons[player] * ((tf[player][tf_num].c * c_guns) + (tf[player][tf_num].b * b_guns));
          point(1, 21);
          printf('Units (max %3d) :', factors / 4);
          point(18, 21);
          iline = get_line(false);
          dum = get_token(iline);
          amount = iline.amount;
          if (amount < 0) {
            factors = 0;
          } else if (amount > 0) {
            factors = min(factors, amount * 4);
          }
          tf[player][tf_num].blasting = true;
          point(1, 22);
          printf('Blasting %3d units', factors / 4);
          blast(pplanet, factors);
          point(1, 23);
          left_line[23] = true;
          putchar(chr(pplanet.pstar + ord('A') - 1));
          pplanet.psee_capacity = pplanet.capacity;
          see = true;
          if ((y_cursor > 21 && x_cursor >= 50) || y_cursor > 24) {
            pause();
            clear_field();
            point(50, 1);
          }
          print_planet(pplanet, see);
        }
      }
    }
  }
}

/// Processes all player moves.
void inputplayer() {
  String key;
  bool fin;
  point(33, 20);
  printf('* Movement *    ');
  fin = false;
  do {
    point(1, 18);
    printf('?                             ');
    point(2, 18);
    key = get_char();
    switch (key) {
      case 'M':
        printmap();
        break;
      case 'B':
        blast_planet();
        break;
      case 'G':
      case ' ':
        fin = true; // end of turn
        break;
      case 'H':
      case '?':
        help(1);
        break;
      case 'L':
        land();
        break;
      case 'D':
        send_tf();
        break;
      case 'S':
        starsum();
        break;
      case 'N':
        make_tf();
        break;
      case 'J':
        join_tf();
        break;
      case 'C':
        print_col();
        break;
      case 'R':
        ressum();
        break;
      case 'Q':
        fin = true;
        quit();
        break;
      case 'T':
        tfsum();
        break;
      default:
        error_message();
        printf('  !illegal command');
    }
  } while (!fin);
}

/// Allows the user to pick a task force and land transports on a planet.
void land() {
  String tfc, trc, planc;
  bool see;
  int x, y, room_left, tfnum, transports, planet_num;
  int starnum;
  Line iline;
  bool found;
  Planet? pplanet;

  printf('and tf:');
  tfc = get_char();
  clear_left();
  tfnum = ord(tfc) - ord('A') + 1;
  if (tfnum < 1 || tfnum > 26) {
    error_message();
    printf('  !illegal tf');
  } else if (tf[player][tfnum].dest == 0) {
    error_message();
    printf('  !nonexistent tf');
  } else if (tf[player][tfnum].eta != 0) {
    error_message();
    printf('  !tf is not in normal space  ');
  } else {
    starnum = tf[player][tfnum].dest;
    pplanet = stars[starnum].first_planet;
    if (pplanet == null) {
      error_message();
      printf('  !no planets at this star    ');
    } else if (tf_stars[starnum][ENEMY] > 0) {
      error_message();
      printf('  !enemy ships present');
    } else {
      point(11, 18);
      printf(' planet ');
      if (pplanet.next == null) {
        planet_num = pplanet.number;
        printf('%d', planet_num);
      } else {
        printf(':');
        planc = get_char();
        planet_num = ord(planc) - ord('0');
        found = false;
        while (pplanet != null && !found) {
          if (pplanet.number == planet_num) {
            found = true;
          } else {
            pplanet = pplanet.next;
          }
        }
        if (!found) {
          planet_num = 0;
          error_message();
          printf(' !Not a habitable planet ');
        }
      }
      if (planet_num != 0 && pplanet != null) {
        if (pplanet.team == ENEMY || (pplanet.team == player && pplanet.conquered)) {
          error_message();
          printf('  !Enemy infested planet  !!  ');
        } else {
          room_left = pplanet.capacity - pplanet.inhabitants;
          point(1, 19);
          printf(' transports:');
          iline = get_line(false);
          trc = get_token(iline);
          transports = iline.amount;
          if (transports == 0) {
            transports = tf[player][tfnum].t;
          }
          if (transports < 1) {
            error_message();
            printf('  !illegal transports');
          } else if (transports > tf[player][tfnum].t) {
            error_message();
            printf('  !only %2d transports in tf', tf[player][tfnum].t);
          } else if (transports > room_left) {
            error_message();
            printf('  !only room for %2d transports', room_left);
          } else {
            pplanet.team = player;
            if (pplanet.inhabitants == 0) {
              col_stars[starnum][player]++;
            }
            pplanet.inhabitants = pplanet.inhabitants + transports;
            pplanet.iu = pplanet.iu + transports;
            tf[player][tfnum].t = tf[player][tfnum].t - transports;
            x = tf[player][tfnum].x;
            y = tf[player][tfnum].y;
            if (board[x][y].enemy == ' ') {
              board[x][y].enemy = '@';
              update_board(x, y, Sector.left);
            }
            point(1, 20);
            putchar(chr(starnum + ord('A') - 1));
            see = true;
            if ((y_cursor > 21 && x_cursor >= 50) || y_cursor > 24) {
              pause();
              clear_field();
              point(50, 1);
            }
            print_planet(pplanet, see);
            zero_tf(player, tfnum);
            print_tf(tfnum);
          }
        }
      }
    }
  }
}

/// Asks the user whether he wants to quit the game.
void quit() {
  clear_screen();
  printf('Quit game....[Y/N]\n');
  final answer = get_char();
  if (answer != 'Y') {
    printmap();
  } else {
    game_over = true;
  }
}

/// Allows the user to move a task force to another star.
void send_tf() {
  String tf_move;
  int tf_num;
  bool error;
  printf('estination tf:');
  tf_move = get_char();
  clear_left();
  point(1, 19);
  tf_num = ord(tf_move) - ord('A') + 1;
  if (tf_num < 1 || tf_num > 26) {
    error_message();
    printf(' !illegal tf');
  } else if (tf[player][tf_num].dest == 0) {
    error_message();
    printf(' !nonexistent tf');
  } else if (tf[player][tf_num].eta != 0 &&
      (tf[player][tf_num].eta != tf[player][tf_num].origeta || tf[player][tf_num].withdrew)) {
    error_message();
    printf(' !Tf is not in normal space');
  } else if (tf[player][tf_num].blasting) {
    error_message();
    printf(' !Tf is blasting a planet');
  } else {
    tf[player][tf_num].withdrew = false;
    set_des(tf_num);
  }
}

bool set_des(int tf_num) {
  bool error;
  int st_num, min_eta;
  String istar;
  double r;
  int rge, dst;
  int from_star;
  if (tf[player][tf_num].eta != 0) {
    tf[player][tf_num].eta = 0;
    from_star = ord(board[tf[player][tf_num].x][tf[player][tf_num].y].star) - ord('A') + 1;
    tf[player][tf_num].dest = from_star;
    tf_stars[from_star][player]++;
    printf('(Cancelling previous orders)');
    point(1, y_cursor + 1);
  }
  error = true;
  printf(' to star:');
  point(10, y_cursor);
  istar = get_char();
  st_num = ord(istar) - ord('A') + 1;
  if ((st_num < 0) || (st_num > nstars)) {
    error_message();
    printf('  !illegal star');
  } else {
    r = sqrt(((stars[st_num].x - tf[1][tf_num].x) * (stars[st_num].x - tf[1][tf_num].x)) +
        ((stars[st_num].y - tf[1][tf_num].y) * (stars[st_num].y - tf[1][tf_num].y)));
    point(1, y_cursor + 1);
    printf('   distance:%5.1f', r);
    dst = (r - 0.049).truncate() + 1;
    if ((dst > range[player]) && ((tf[1][tf_num].b != 0) || (tf[1][tf_num].c != 0) || (tf[1][tf_num].t != 0))) {
      error_message();
      printf('  !maximum range is %2d', range[player]);
    } else if (r < 0.5) {
      point(1, y_cursor + 1);
      printf('Tf remains at star');
    } else {
      min_eta = ((dst - 1) / vel[player]).truncate() + 1;
      point(1, y_cursor + 1);
      printf('eta in %2d turns', min_eta);
      tf_stars[tf[player][tf_num].dest][player]--;
      tf[player][tf_num].dest = st_num;
      tf[player][tf_num].eta = min_eta;
      tf[player][tf_num].origeta = tf[player][tf_num].eta;
      tf[player][tf_num].xf = tf[player][tf_num].x;
      tf[player][tf_num].yf = tf[player][tf_num].y;
      error = false;
    }
  }
  return error;
}

/// Returns the next character the user enters on the keyboard.
/// Returns the empty string on EOF.
String get_char() {
  var result = getchar() ?? '';
  if (result == '\r') {
    result = '\n';
  }
  result = result.toUpperCase();
  putchar(result);
  return result;
}

class Line {
  List<String> iline = List.filled(81, ' ');
  int index = 1;
  int amount = 0;
}

/// Returns a line of input which can be passed to [get_token].
/// If [onech] is true, each character entered is separated by space.
Line get_line(bool onech) {
  final line = Line();
  String ch;
  int ind;
  ind = 1;
  do {
    ch = get_char();
    if (ch == '\b') {
      if (ind != 1) {
        ind = ind - 1;
        if ((ind != 1) && onech) {
          putchar('\b');
          ind = ind - 1;
        }
        if ((ind != 1) && !onech) {
          putchar(' ');
          putchar('\b');
        }
      }
    } else if (ch != '\n') {
      line.iline[ind] = ch;
      ind = ind + 1;
      if (onech) {
        putchar(' ');
        line.iline[ind] = ' ';
        ind = ind + 1;
      }
    }
  } while (ind < 25 && ch != '\n');
  while (ind != 80) {
    line.iline[ind] = ' ';
    ind = ind + 1;
  }
  return line;
}

/// Fills [slist] with the distances to star [s_star] and returns the number of reachable stars.
/// Distance 0.0 indicates a non-reachable star.
int get_stars(int s_star, List<double> slist) {
  int starnum, count;
  count = 0;
  for (starnum = 1; starnum <= nstars; starnum++) {
    if (range[0] >= r2nge[s_star][starnum]) {
      count = count + 1;
      slist[starnum] = r2nge[s_star][starnum].toDouble();
    } else {
      slist[starnum] = 0.0;
    }
  }
  return count;
}

/// Clears the last 30 columns from the current [y_cursor] position to [bottom_field].
void clear_field() {
  int new_bottom, y;
  new_bottom = y_cursor - 1;
  if (new_bottom < bottom_field) {
    for (y = new_bottom + 1; y <= bottom_field; y++) {
      point(50, y);
      printf('\x1B[K');
    }
  }
  bottom_field = new_bottom;
}

/// Clears the first 30 columns of line 19 to 24.
/// Only clears the line if indicated dirty by [left_line] list and resets dirty state.
void clear_left() {
  for (var i = 19; i <= 24; i++) {
    if (left_line[i]) {
      point(1, i);
      printf(blank_line);
      left_line[i] = false;
    }
  }
}

/// Clears the screen and moves the cursor to 1/1.
void clear_screen() {
  printf('\x1B[2J');
  point(1, 1);
}

/// Moves the cursor to position 1/24 (to display an error).
void error_message() {
  point(1, 24);
}

/// Gets the next character from [line]. It might be prefixed by a number.
/// That number is parsed and available in [Line.amount].
String get_token(Line line) {
  int index, value;
  String token;

  index = line.index;
  value = 0;
  token = ' ';

  // skip whitespace
  while (line.iline[index] == ' ' && index < 80) {
    index += 1;
  }
  if (index < 80) {
    if (!isdigit(line.iline[index])) {
      value = 1;
    } else {
      while (isdigit(line.iline[index])) {
        value = 10 * value + ord(line.iline[index]) - ord('0');
        index = index + 1;
      }
    }
    token = line.iline[index];
    index = index + 1;
  }

  // skip to the next word
  while (line.iline[index] != ' ' && index < 80) {
    index += 1;
  }
  while (line.iline[index] == ' ' && index < 80) {
    index = index + 1;
  }

  line.index = index;
  line.amount = value;
  return token;
}

class Helpst {
  const Helpst(this.cmd, this.does);
  final String cmd, does;
}

List<Helpst> help0 = [
  Helpst('B', 'Bld Battlestar(s)    75'),
  Helpst('C', 'Bld Cruiser(s)       16'),
  Helpst('H', 'Help'),
  Helpst('R', 'Range Research'),
  Helpst('S', 'Bld Scout(s)          6'),
  Helpst('V', 'Velocity Research'),
  Helpst('W', 'Weapons Research'),
  Helpst('>M', 'Redraw Map'),
  Helpst('>R', 'Research summary')
];

List<Helpst> help1 = [
  Helpst('B', 'Blast Planet'),
  Helpst('C', 'Colony summary'),
  Helpst('D', 'TaskForce Destination'),
  Helpst('G', 'Go on (done)'),
  Helpst('H', 'Help'),
  Helpst('J', 'Join TaskForces'),
  Helpst('L', 'Land transports'),
  Helpst('M', 'Redraw Map'),
  Helpst('N', 'New TaskForce'),
  Helpst('Q', 'Quit'),
  Helpst('R', 'Research summary'),
  Helpst('S', 'Star summary'),
  Helpst('T', 'TaskForce summary')
];

List<Helpst> help2 = [
  Helpst('C', 'Colonies'),
  Helpst('G', 'Go on (done)'),
  Helpst('H', 'Help'),
  Helpst('M', 'Map'),
  Helpst('O', 'Odds'),
  Helpst('R', 'Research summary'),
  Helpst('S', 'Star summary'),
  Helpst('T', 'TaskForce summary'),
  Helpst('W', 'Withdraw')
];

List<Helpst> help3 = [
  Helpst('B', 'Break off Attack'),
  Helpst('C', 'Colony summary'),
  Helpst('G', 'Go on (done)'),
  Helpst('H', 'Help'),
  Helpst('J', 'Join TFs'),
  Helpst('M', 'Redraw Map'),
  Helpst('N', 'New TF'),
  Helpst('R', 'Research summary'),
  Helpst('S', 'Star summary'),
  Helpst('T', 'TaskForce summary')
];

List<Helpst> help4 = [
  Helpst('A', 'Bld Adv. Missle Base 35'),
  Helpst('B', 'Bld Battlestar(s)    70'),
  Helpst('C', 'Bld Cruiser(s)       16'),
  Helpst('H', 'Help'),
  Helpst('I', 'Invest                3'),
  Helpst('M', 'Bld Missle Base(s)    8'),
  Helpst('R', 'Range Research'),
  Helpst('S', 'Bld Scout(s)          6'),
  Helpst('T', 'Bld Transports'),
  Helpst('V', 'Vel Research'),
  Helpst('W', 'Weapons Research'),
  Helpst('>C', 'Colony summary'),
  Helpst('>M', 'Redraw Map'),
  Helpst('>R', 'Research summary'),
  Helpst('>S', 'Star summary')
];

/// Prints a list of command in the last 30 columns of the screen.
void help(int which) {
  List<Helpst>? h;
  var j = 1;
  if (which == 0) {
    h = help0;
  }
  if (which == 1) {
    h = help1;
  }
  if (which == 2) {
    h = help2;
  }
  if (which == 3) {
    h = help3;
  }
  if (which == 4) {
    h = help4;
  }
  if (h != null) {
    point(50, j++);
    for (final hh in h) {
      printf('%2s - %-25s', hh.cmd, hh.does);
      point(50, j++);
    }
    clear_field();
  }
}

/// Updates the board at the given position.
/// A star with player-owned colonies is marked with "@".
/// A single player task force is displayed by name.
/// Multiple task forces are displayed by "*".
void on_board(int x, int y) {
  int i;
  int starnum;
  board[x][y].tf = ' ';
  i = 1;
  do {
    if ((tf[player][i].dest != 0) && (tf[player][i].x == x) && (tf[player][i].y == y)) {
      if (board[x][y].tf == ' ') {
        board[x][y].tf = chr(i + ord('a') - 1);
      } else {
        board[x][y].tf = '*';
        i = 27;
      }
    }
    i = i + 1;
  } while (i <= 26);
  if (board[x][y].star != '.') {
    board[x][y].enemy = ' ';
    starnum = ord(board[x][y].star) - ord('A') + 1;
    if (col_stars[starnum][player] != 0) {
      board[x][y].enemy = '@';
    }
  }
  update_board(x, y, Sector.both);
}

/// Asks the user to press any key to continue.
void pause() {
  point(1, 18);
  printf('Press any key to continue  ');
  get_char();
}

/// Prints a player task force at the current cursor position.
/// Then advances cursor position to the next line in the same column.
void print_tf(int i) {
  if (i > 0 && i < 27) {
    final t = tf[player][i];
    if (t.dest != 0) {
      printf('TF%c:', chr(i + ord('a') - 1));
      if (t.eta == 0) {
        putchar(chr(t.dest + ord('A') - 1));
      } else {
        putchar(' ');
      }
      printf('(%2d,%2d)               ', t.x, t.y);
      point(x_cursor + 14, y_cursor);
      x_cursor = x_cursor - 14;
      disp_tf(t);
      if (t.eta != 0) {
        // still on its way
        printf('\x1B[7m');
        printf('%c%d', chr(t.dest + ord('A') - 1), t.eta);
        printf('\x1B[0m');
      }
      point(x_cursor, y_cursor + 1);
    }
  }
}

/// Prints information about the star [stnum].
void print_star(int stnum) {
  bool see;
  int i, x, y;
  Planet? p;
  if ((stnum != 0) && (stnum <= nstars)) {
    if ((y_cursor + 3 + tf_stars[stnum][player] + tf_stars[stnum][ENEMY]) > 19) {
      clear_field();
      pause();
      point(50, 1);
    }
    if (stars[stnum].visit[player] == true) {
      see = false;
      printf('----- star %c -----            ', chr(stnum + ord('A') - 1));
      point(50, y_cursor + 1);
      x = stars[stnum].x;
      y = stars[stnum].y;
      if (tf_stars[stnum][player] != 0) {
        see = true;
        for (i = 1; i <= 26; i++) {
          if (tf[player][i].dest == stnum && tf[player][i].eta == 0) {
            printf('TF%c                           ', chr(i + ord('a') - 1));
            point(55, y_cursor);
            disp_tf(tf[player][i]);
            point(50, y_cursor + 1);
          }
        }
      }
      if (!see) {
        see = col_stars[stnum][player] != 0;
      }
      if (see && (tf_stars[stnum][ENEMY] != 0)) {
        i = 1;
        while (tf[ENEMY][i].eta != 0 || (tf[ENEMY][i].dest != stnum)) {
          i = i + 1;
        }
        printf(' EN:                          ');
        point(55, y_cursor);
        disp_tf(tf[ENEMY][i]);
        point(50, y_cursor + 1);
      }
      p = stars[stnum].first_planet;
      if (p == null) {
        printf('  no useable planets          ');
        point(50, y_cursor + 1);
      } else {
        while (p != null) {
          putchar(' ');
          if (((y_cursor > 21) && (x_cursor >= 50)) || (y_cursor > 24)) {
            pause();
            clear_field();
            point(50, 1);
          }
          print_planet(p, see);
          p = p.next;
        }
      }
    }
  }
}

/// Prints information about research, either only a specific field or all fields.
void ressum() {
  String key;
  Line iline;
  printf('esearch field(s):');
  iline = get_line(true);
  key = get_token(iline);
  clear_left();
  if (key == ' ') {
    pr2nt_res('R');
    pr2nt_res('V');
    pr2nt_res('W');
  } else {
    do {
      pr2nt_res(key);
      key = get_token(iline);
    } while (key != ' ');
  }
}

/// Prints information about the given field of research.
void pr2nt_res(String field) {
  switch (field) {
    case 'V':
      point(53, 18);
      printf('V:%2d', vel[player]);
      if (vel[player] < max_vel) {
        printf(' res: %3d need:%4d', vel_working[player], vel_req[vel[player] + 1]);
      } else {
        printf('                   '); // 19 spaces
      }
      break;
    case 'R':
      point(53, 19);
      printf('R:%2d', range[player]);
      if (range[player] < bdsize) {
        printf(' res: %3d need:%4d', ran_working[player], ran_req[range[player] + 1]);
      } else {
        printf('                   '); // 19 spaces
      }
      break;
    case 'W':
      point(53, 20);
      printf('W:%2d', weapons[player]);
      if (weapons[player] < 10) {
        printf(' res: %3d need:%4d', weap_working[player], weap_req[weapons[player] + 1]);
      } else {
        printf('                   '); // 19 spaces
      }
      break;
  }
}

/// Adds points to a specific field of research.
/// If the enemy is researching and a new level was reached, pick a new field.
void research(int team, String field, int amt) {
  switch (field) {
    case 'W':
      if (weapons[team] < 10) {
        weap_working[team] += amt;
        amt = 0;
        if (weap_working[team] >= weap_req[weapons[team] + 1]) {
          amt = weap_working[team] - weap_req[weapons[team] + 1];
          weapons[team] += 1;
          if (team == ENEMY) {
            new_research();
            field = en_research;
          }
          weap_working[team] = 0;
          research(team, field, amt);
        }
      }
      break;
    case 'R':
      if (range[team] < bdsize) {
        ran_working[team] += amt;
        amt = 0;
        if (ran_working[team] >= ran_req[range[team] + 1]) {
          amt = ran_working[team] - ran_req[range[team] + 1];
          range[team] += 1;
          if (team == ENEMY) {
            new_research();
            field = en_research;
          }
          ran_working[team] = 0;
          research(team, field, amt);
        }
      }
      break;
    case 'V':
      if (vel[team] < max_vel) {
        vel_working[team] += amt;
        amt = 0;
        if (vel_working[team] >= vel_req[vel[team] + 1]) {
          amt = vel_working[team] - vel_req[vel[team] + 1];
          vel[team] += 1;
          if (team == ENEMY) {
            new_research();
            field = en_research;
          }
          vel_working[team] = 0;
          research(team, field, amt);
        }
      }
      break;
    default:
      printf('error!!!! in research field %c\n', field);
  }
}

/// Creates a new  from an existing one by selecting ships.
void make_tf() {
  String task;
  int tf_num;
  bool error;
  int new_tf;
  printf('ew tf- from tf:');
  task = get_char();
  clear_left();
  tf_num = ord(task) - ord('A') + 1;
  error = (tf_num < 1) || (tf_num > 26);
  if (!error) {
    error = (tf[player][tf_num].eta != 0) || (tf[player][tf_num].dest == 0);
  }
  if (error) {
    error_message();
    printf('  !illegal tf');
  } else if (tf[player][tf_num].blasting) {
    error = true;
    error_message();
    printf(' !Tf is blasting a planet     ');
  } else {
    point(1, 19);
    new_tf = split_tf(tf_num);
    point(1, 20);
    print_tf(new_tf);
    point(1, 21);
    print_tf(tf_num);
  }
}

int split_tf(int tf_num) {
  int new_tf;
  String ships;
  int x, y, n_ships;
  Line iline;
  new_tf = get_tf(player, tf[player][tf_num].dest);
  tf_stars[tf[player][tf_num].dest][player]++;
  printf(' ships:');
  point(8, y_cursor);
  iline = get_line(false);
  ships = get_token(iline);
  n_ships = iline.amount;
  if (ships == ' ') {
    tf[player][new_tf].s = tf[player][tf_num].s;
    tf[player][new_tf].t = tf[player][tf_num].t;
    tf[player][new_tf].c = tf[player][tf_num].c;
    tf[player][new_tf].b = tf[player][tf_num].b;
    tf[player][tf_num].s = 0;
    tf[player][tf_num].t = 0;
    tf[player][tf_num].c = 0;
    tf[player][tf_num].b = 0;
  } else {
    do {
      switch (ships) {
        case 'T':
          if (tf[player][tf_num].t < n_ships) {
            n_ships = tf[player][tf_num].t;
          }
          tf[player][tf_num].t = tf[player][tf_num].t - n_ships;
          tf[player][new_tf].t = tf[player][new_tf].t + n_ships;
          break;
        case 'S':
          if (tf[player][tf_num].s < n_ships) {
            n_ships = tf[player][tf_num].s;
          }
          tf[player][tf_num].s = tf[player][tf_num].s - n_ships;
          tf[player][new_tf].s = tf[player][new_tf].s + n_ships;
          break;
        case 'C':
          if (tf[player][tf_num].c < n_ships) {
            n_ships = tf[player][tf_num].c;
          }
          tf[player][tf_num].c = tf[player][tf_num].c - n_ships;
          tf[player][new_tf].c = tf[player][new_tf].c + n_ships;
          break;
        case 'B':
          if (tf[player][tf_num].b < n_ships) {
            n_ships = tf[player][tf_num].b;
          }
          tf[player][tf_num].b = tf[player][tf_num].b - n_ships;
          tf[player][new_tf].b = tf[player][new_tf].b + n_ships;
          break;
        default:
          error_message();
          printf('  ! Illegal field %c', ships);
      }
      ships = get_token(iline);
      n_ships = iline.amount;
    } while (ships != ' ');
  }
  x = tf[player][tf_num].x;
  y = tf[player][tf_num].y;
  zero_tf(player, tf_num);
  zero_tf(player, new_tf);
  on_board(x, y);
  return new_tf;
}

/// Combines task forces.
void join_tf() {
  String tf1, tf2;
  int tf1n, tf2n;
  Line iline;
  printf('oin tfs:');
  iline = get_line(true);
  clear_left();
  tf1 = get_token(iline);
  tf1n = ord(tf1) - ord('A') + 1;
  if ((tf1n < 1) || (tf1n > 26)) {
    error_message();
    printf('  ! illegal tf %c', tf1);
  } else if ((tf[player][tf1n].eta) > 0) {
    error_message();
    printf('  !tf%c is not in normal space ', tf1);
  } else if (tf[player][tf1n].dest == 0) {
    error_message();
    printf('  !nonexistent tf');
  } else if (tf[player][tf1n].blasting) {
    error_message();
    printf('  !Tf is blasting a planet    ');
  } else {
    tf2 = get_token(iline);
    while (tf2 != ' ') {
      tf2n = ord(tf2) - ord('A') + 1;
      if (tf2n < 1 || tf2n > 26) {
        error_message();
        printf('  !illegal tf %c', tf2);
      } else if (tf2n == tf1n) {
        error_message();
        printf('!Duplicate tf %c', tf2);
      } else if (tf[player][tf2n].dest == 0) {
        error_message();
        printf('!Nonexistant TF%c', tf2);
      } else if ((tf[player][tf2n].x != tf[player][tf1n].x) || (tf[player][tf2n].y != tf[player][tf2n].y)) {
        error_message();
        printf('  !tf%c bad location', tf2);
      } else if (tf[player][tf2n].eta != 0) {
        error_message();
        printf('  !tf%c is not in normal space ', tf2);
      } else if (tf[player][tf2n].blasting) {
        error_message();
        printf(' !Tf%c is blasting a planet    ', tf2);
      } else {
        joinsilent(player, tf[player][tf1n], tf[player][tf2n]);
      }
      tf2 = get_token(iline);
    }
    on_board(tf[player][tf1n].x, tf[player][tf1n].y);
    point(1, 19);
    print_tf(tf1n);
  }
}

void inv_enemy(int x, int y, Planet planet) {
  int num, inv_amount, balance, min_mb, transports, new_tf;
  int trash1, trash2;
  balance = planet.iu;
  if (tf_stars[planet.pstar][ENEMY] == 0) {
    new_tf = get_tf(ENEMY, planet.pstar);
    tf_stars[planet.pstar][ENEMY] = 1;
  } else {
    new_tf = 1;
    while ((tf[ENEMY][new_tf].dest != planet.pstar) || (tf[ENEMY][new_tf].eta != 0)) {
      new_tf = new_tf + 1;
    }
  }
  min_mb = (planet.capacity / 20).truncate();
  while ((planet.amb == 0) && (!planet.conquered) && (planet.mb < min_mb) && (balance >= mb_cost)) {
    balance = balance - mb_cost;
    planet.mb = planet.mb + 1;
  }
  if ((balance >= b_cost) && (rnd(5) != 1) && (rnd(7) <= planet.amb + 3) && (planet.amb > 1)) {
    balance = balance - b_cost;
    tf[ENEMY][new_tf].b++;
  }
  if ((balance >= amb_cost) && ((planet.amb < 4) || (rnd(2) == 2)) && (!planet.conquered)) {
    balance = balance - amb_cost;
    planet.amb++;
  }
  while (balance >= 9) {
    switch (rnd(12)) {
      case 1:
      case 2:
        research(ENEMY, en_research, 8);
        balance = balance - 8;
        break;
      case 3:
      case 4:
      case 10:
        if (balance >= c_cost) {
          balance = balance - c_cost;
          tf[ENEMY][new_tf].c++;
        } else if ((!planet.conquered) && (balance >= mb_cost)) {
          balance = balance - mb_cost;
          planet.mb = planet.mb + 1;
        } else {
          balance = balance - 9;
          research(ENEMY, en_research, 9);
        }
        break;
      case 11:
      case 12:
        if ((planet.inhabitants / planet.capacity < 0.6) ||
            ((planet.capacity >= b_cost / iu_ratio) && (planet.iu < b_cost + 10))) {
          inv_amount = min(3, planet.inhabitants * iu_ratio - planet.iu);
          balance = balance - inv_amount * i_cost;
          planet.iu = planet.iu + inv_amount;
        } else if (!planet.conquered) {
          transports = min(rnd(2) + 6, planet.inhabitants - 1);
          if (planet.iu > b_cost) {
            transports = min(transports, planet.iu - b_cost);
          }
          balance = balance - transports;
          planet.inhabitants = planet.inhabitants - transports;
          trash1 = planet.iu - transports;
          trash2 = planet.inhabitants * iu_ratio;
          planet.iu = min(trash1, trash2);
          tf[ENEMY][new_tf].t = tf[ENEMY][new_tf].t + transports;
        }
        break;
      default:
        inv_amount = min(3, planet.inhabitants * iu_ratio - planet.iu);
        balance = balance - i_cost * inv_amount;
        planet.iu = planet.iu + inv_amount;
        break;
    }
  }
  zero_tf(ENEMY, new_tf);
  research(ENEMY, en_research, balance);
}

void inv_player(int x, int y, Planet planet) {
  bool printtf;
  Line iline;
  String key;
  int cost, amount, new_tf, balance;
  int trash1, trash2;
  new_tf = get_tf(player, planet.pstar);
  tf_stars[planet.pstar][player]++;
  printtf = false;
  balance = planet.iu;
  clear_left();
  point(1, 19);
  putchar(chr(planet.pstar + ord('A') - 1));
  printf('%d:%2d                         ', planet.number, planet.psee_capacity);
  point(x_cursor + 5, y_cursor);
  x_cursor = x_cursor - 5;
  printf('(%2d,/%3d)', planet.inhabitants, planet.iu);
  if (planet.conquered) {
    printf('Con');
  } else {
    printf('   ');
  }
  if (planet.mb != 0) {
    printf('%2dmb', planet.mb);
  } else {
    printf('    ');
  }
  if (planet.amb != 0) {
    printf('%2damb', planet.amb);
  }
  point(x_cursor, y_cursor + 1);
  do {
    point(1, 18);
    printf('%3d?                          ', balance);
    point(5, 18);
    iline = get_line(false);
    do {
      key = get_token(iline);
      amount = iline.amount;
      switch (key) {
        case 'A':
          cost = amount * amb_cost;
          if (planet.inhabitants == 0) {
            cost = 0;
            error_message();
            printf('  !abandoned planet');
          } else if (planet.conquered) {
            cost = 0;
            error_message();
            printf(' !No amb  on conquered colony ');
          } else if (cost <= balance) {
            planet.amb = planet.amb + amount;
          }
          break;
        case 'B':
          cost = amount * b_cost;
          if (cost <= balance) {
            tf[player][new_tf].b = tf[player][new_tf].b + amount;
            printtf = true;
          }
          break;
        case 'C':
          cost = amount * c_cost;
          if (cost <= balance) {
            tf[player][new_tf].c = tf[player][new_tf].c + amount;
            printtf = true;
          }
          break;
        case 'H':
          help(4);
          cost = 0;
          break;
        case 'M':
          cost = amount * mb_cost;
          if (planet.inhabitants == 0) {
            cost = 0;
            error_message();
            printf('  !abandoned planet');
          } else if (planet.conquered) {
            cost = 0;
            error_message();
            printf(' !No Mb  on conquered colony  ');
          } else if (cost <= balance) {
            planet.mb = planet.mb + amount;
          }
          break;
        case 'S':
          cost = amount * s_cost;
          if (cost <= balance) {
            tf[player][new_tf].s = tf[player][new_tf].s + amount;
            printtf = true;
          }
          break;
        case 'T':
          cost = amount;
          if (cost <= balance) {
            if (cost > planet.inhabitants) {
              error_message();
              printf(' ! Not enough people for ( trans');
              cost = 0;
            } else if (planet.conquered) {
              cost = 0;
              error_message();
              printf('!No transports on conqered col');
            } else {
              tf[player][new_tf].t = tf[player][new_tf].t + amount;
              planet.inhabitants = planet.inhabitants - amount;
              trash1 = planet.iu - amount;
              trash2 = planet.inhabitants * iu_ratio;
              planet.iu = min(trash1, trash2);
              printtf = true;
              if (planet.inhabitants == 0) {
                col_stars[planet.pstar][player]--;
                if (col_stars[planet.pstar][player] == 0) {
                  board[x][y].enemy = ' ';
                  update_board(x, y, Sector.left);
                }
                planet.team = none;
                planet.amb = 0;
                planet.mb = 0;
                planet.iu = 0;
              }
            }
          }
          break;
        case 'I':
          cost = i_cost * amount;
          if ((amount + planet.iu) > (planet.inhabitants * iu_ratio)) {
            cost = 0;
            error_message();
            printf(" !Can't support that many iu's");
          } else if (cost <= balance) {
            planet.iu = planet.iu + amount;
          }
          break;
        case 'R':
        case 'V':
        case 'W':
          cost = amount;
          if (cost <= balance) {
            point(1, 21);
            research(player, key, amount);
          }
          pr2nt_res(key);
          break;
        case ' ':
          cost = 0;
          break;
        case '>':
          cost = 0;
          point(1, 18);
          printf('>?     ');
          point(3, 18);
          key = get_char();
          switch (key) {
            case 'M':
              printmap();
              break;
            case 'S':
              starsum();
              break;
            case 'C':
              print_col();
              break;
            case 'R':
              ressum();
              break;
            default:
              error_message();
              printf(' !Only M,S,C,R allowed      ');
          }
          break;
        default:
          cost = 0;
          error_message();
          printf(' !Illegal field %c', key);
      }
      if (cost > balance) {
        error_message();
        printf(" !can't affort %3d%c", amount, key);
      } else {
        balance = balance - cost;
      }
    } while (key != ' ');
    clear_left();
    point(1, 19);
    putchar(chr(planet.pstar + ord('A') - 1));
    printf('%d:%2d                         ', planet.number, planet.psee_capacity);
    point(x_cursor + 5, y_cursor);
    x_cursor = x_cursor - 5;
    printf('(%2d,/%3d)', planet.inhabitants, planet.iu);
    if (planet.conquered) {
      printf('Con');
    } else {
      printf('   ');
    }
    if (planet.mb != 0) {
      printf('%2dmb', planet.mb);
    } else {
      printf('    ');
    }
    if (planet.amb != 0) {
      printf('%2damb', planet.amb);
    }
    point(x_cursor, y_cursor + 1);
    if (printtf) {
      point(1, 20);
      print_tf(new_tf);
    }
  } while (balance > 0);
  zero_tf(player, new_tf);
  on_board(x, y);
}

/// Processes player and enemy investments.
/// Also increases the population and updates the "guess" for defenses the enemy saw on player-owned planets.
void invest() {
  int newborn, starnum;
  Planet? pplan;
  production_year = 0;
  point(33, 20);
  printf('* investment *  ');
  for (starnum = 1; starnum <= nstars; starnum++) {
    pplan = stars[starnum].first_planet;
    while (pplan != null) {
      if (pplan.esee_team == player && pplan.capacity > 10 && pplan.esee_def < 12) {
        pplan.esee_def += 1;
      }
      if (pplan.team != none) {
        newborn = round(pplan.inhabitants * growth_rate[pplan.team] * (1 - pplan.inhabitants / pplan.capacity));
        if (pplan.conquered) {
          newborn = (newborn / 2).truncate();
        }
        pplan.inhabitants += newborn;
        pplan.iu += newborn;
        if (pplan.team == ENEMY) {
          inv_enemy(stars[starnum].x, stars[starnum].y, pplan);
        } else {
          inv_player(stars[starnum].x, stars[starnum].y, pplan);
        }
      }
      pplan = pplan.next;
    }
  }
  battle();
}

void main() {
  setRawMode(true);
  try {
    printf('\n *** CONQUEST *** \n');
    initconst();
    initmach();
    do {
      inputplayer();
      if (!game_over) {
        inputmach();
        move_ships();
        battle();
        if (production_year == 4 && turn < 100) {
          invest();
        }
        up_year();
      }
      check_game_over();
    } while (!game_over);
  } finally {
    setRawMode(false);
  }
}
