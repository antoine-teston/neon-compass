// Catégories et textes d'effet : la part éditoriale, séparée de l'extraction.
//
// Les descriptions sont rédigées dans nos mots (contrainte IP) — check-originality
// vérifie qu'aucune ne se retrouve telle quelle dans la source. Les noms de
// véhicules du jeu sont des identifiants factuels et restent tels quels : un code
// qui ne dit pas ce qu'il fait apparaître ne sert à rien.

export const categories = {
  spawn_trashmaster: 'vehicles', spawn_stretch: 'vehicles', spawn_mallard: 'vehicles',
  spawn_sanchez: 'vehicles', spawn_comet: 'vehicles', spawn_buzzard_attack_chopper: 'vehicles',
  spawn_caddy: 'vehicles', spawn_duster: 'vehicles', spawn_rapid_gt: 'vehicles',
  spawn_pcj_600: 'vehicles', spawn_bmx: 'vehicles', spawn_dodo: 'vehicles',
  spawn_duke_o_death: 'vehicles', spawn_kraken: 'vehicles',

  invincibility: 'player', max_health_armor: 'player', parachute: 'player',
  recharge_special: 'player', fast_run: 'player', fast_swim: 'player',
  super_jump: 'player', skyfall: 'player', drunk_mode: 'player',

  weapons: 'weapons', flaming_bullets: 'weapons', explosive_ammo: 'weapons',
  explosive_melee: 'weapons',

  change_weather: 'world', moon_gravity: 'world', slow_motion: 'world',
  slow_motion_aim: 'world', slippery_cars: 'world',

  raise_wanted: 'misc', lower_wanted: 'misc', director_mode: 'misc',
  black_cellphone: 'misc',
};

export const effects = {
  spawn_trashmaster: { en: 'Drops a Trashmaster garbage truck next to you.', fr: 'Fait apparaître un camion-poubelle Trashmaster à côté de vous.' },
  spawn_stretch: { en: 'Drops a Stretch limousine next to you.', fr: 'Fait apparaître une limousine Stretch à côté de vous.' },
  spawn_mallard: { en: 'Drops a Mallard stunt biplane next to you.', fr: 'Fait apparaître un biplan de voltige Mallard à côté de vous.' },
  spawn_sanchez: { en: 'Drops a Sanchez dirt bike next to you.', fr: 'Fait apparaître une moto tout-terrain Sanchez à côté de vous.' },
  spawn_comet: { en: 'Drops a Comet sports car next to you.', fr: 'Fait apparaître une voiture de sport Comet à côté de vous.' },
  spawn_buzzard_attack_chopper: { en: 'Drops an armed Buzzard helicopter next to you.', fr: 'Fait apparaître un hélicoptère armé Buzzard à côté de vous.' },
  spawn_caddy: { en: 'Drops a Caddy golf cart next to you.', fr: 'Fait apparaître une voiturette de golf Caddy à côté de vous.' },
  spawn_duster: { en: 'Drops a Duster crop-dusting plane next to you.', fr: 'Fait apparaître un avion d’épandage Duster à côté de vous.' },
  spawn_rapid_gt: { en: 'Drops a Rapid GT sports car next to you.', fr: 'Fait apparaître une voiture de sport Rapid GT à côté de vous.' },
  spawn_pcj_600: { en: 'Drops a PCJ-600 motorcycle next to you.', fr: 'Fait apparaître une moto PCJ-600 à côté de vous.' },
  spawn_bmx: { en: 'Drops a BMX bike next to you.', fr: 'Fait apparaître un BMX à côté de vous.' },
  spawn_dodo: { en: 'Drops a Dodo seaplane next to you.', fr: 'Fait apparaître un hydravion Dodo à côté de vous.' },
  spawn_duke_o_death: { en: 'Drops the armoured Duke O’Death next to you.', fr: 'Fait apparaître la Duke O’Death blindée à côté de vous.' },
  spawn_kraken: { en: 'Drops a Kraken submarine next to you.', fr: 'Fait apparaître un sous-marin Kraken à côté de vous.' },

  invincibility: { en: 'Makes you immune to damage for five minutes. Enter it again to renew.', fr: 'Vous rend insensible aux dégâts pendant cinq minutes. À resaisir pour prolonger.' },
  max_health_armor: { en: 'Refills your health and armour to full.', fr: 'Remet votre santé et votre gilet au maximum.' },
  parachute: { en: 'Puts a parachute in your inventory.', fr: 'Ajoute un parachute à votre inventaire.' },
  recharge_special: { en: 'Refills your character’s special ability meter.', fr: 'Recharge la jauge de capacité spéciale de votre personnage.' },
  fast_run: { en: 'Doubles how fast you run.', fr: 'Double votre vitesse de course.' },
  fast_swim: { en: 'Doubles how fast you swim.', fr: 'Double votre vitesse de nage.' },
  super_jump: { en: 'Turns every jump into a huge leap.', fr: 'Transforme chaque saut en bond démesuré.' },
  skyfall: { en: 'Teleports you high above the map and drops you in free fall.', fr: 'Vous téléporte très haut au-dessus de la carte et vous lâche en chute libre.' },
  drunk_mode: { en: 'Blurs the picture and makes your character stagger.', fr: 'Trouble l’image et fait tituber votre personnage.' },

  weapons: { en: 'Gives you the full arsenal, ammunition included.', fr: 'Vous donne tout l’arsenal, munitions comprises.' },
  flaming_bullets: { en: 'Your bullets set what they hit on fire.', fr: 'Vos balles enflamment ce qu’elles touchent.' },
  explosive_ammo: { en: 'Your bullets detonate on impact.', fr: 'Vos balles explosent à l’impact.' },
  explosive_melee: { en: 'Your punches blow away whatever they land on.', fr: 'Vos coups de poing font exploser ce qu’ils atteignent.' },

  change_weather: { en: 'Switches the weather to the next setting in the cycle.', fr: 'Passe la météo au réglage suivant du cycle.' },
  moon_gravity: { en: 'Weakens gravity, so vehicles and bodies drift.', fr: 'Affaiblit la gravité : véhicules et corps se mettent à flotter.' },
  slow_motion: { en: 'Slows the whole world down. Stacks up to three times; a fourth entry turns it off.', fr: 'Ralentit le monde entier. Cumulable trois fois ; une quatrième saisie désactive.' },
  slow_motion_aim: { en: 'Slows time only while you aim. Stacks up to three times; a fourth entry turns it off.', fr: 'Ralentit le temps seulement pendant que vous visez. Cumulable trois fois ; une quatrième saisie désactive.' },
  slippery_cars: { en: 'Strips tyre grip, so every car slides.', fr: 'Supprime l’adhérence des pneus : toutes les voitures glissent.' },

  raise_wanted: { en: 'Adds one star to your wanted level.', fr: 'Ajoute une étoile à votre niveau de recherche.' },
  lower_wanted: { en: 'Removes one star from your wanted level.', fr: 'Retire une étoile à votre niveau de recherche.' },
  director_mode: { en: 'Opens Director Mode, the free-roam scene editor.', fr: 'Ouvre le mode Réalisateur, l’éditeur de scènes en roue libre.' },
  black_cellphone: { en: 'Switches your in-game phone to its black theme.', fr: 'Passe le téléphone du jeu sur son thème noir.' },
};
