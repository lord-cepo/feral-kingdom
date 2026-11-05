class_name Enum
extends RefCounted

enum {ANY, YOU, OPP, NONE, HERO, TROOP, TEMPLE, STARTING, INTERMEDIATE, FRONT, SUBJECT, TARGET, SELF, HEX, UNIT, PLAYER, AWAY, TOWARDS, FROM, UNDEPLOYED, DEPLOYED, DEFEATED}

# used in query_selector.gd
enum owner {ANY, P1, P2, BOTH, NONE}
enum type {ANY, HERO, TROOP, TEMPLE}
enum side {ANY, P1, P2, NONE}
enum prop {ANY, BOMB_ON, BOMB_OFF, BOMB, NONE}
enum control {ANY, P1, P2, NONE}
enum region {ANY, STARTING, INTERMEDIATE, FRONT}

# distance_selector.gd
enum who {SUBJ, TRGT, SELF}
# used in prop.gd
enum p_increment {FLAG, COUNTER}
enum p_target {HEX, UNIT, PLAYER, STATIC}

# used in distance_selector.gd
enum direction {AWAY, TOWARDS, FROM}

#
enum t_state {UNDEPLOYED, DEPLOYED, DEFEATED}
