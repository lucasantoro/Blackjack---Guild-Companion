local _, BJ = ...

BJ.Data = {}
local Data = BJ.Data

Data.categories = {
    { id = "MPLUS", label = "Mythic+", short = "M+", icon = "Interface\\Icons\\Achievement_ChallengeMode_Gold", color = {0.34,0.70,1.00} },
    { id = "RAID", label = "Raid", short = "R", icon = "Interface\\Icons\\Achievement_Raid_GloryoftheRaider", color = {1.00,0.42,0.39} },
    { id = "DELVE", label = "Delve", short = "D", icon = "Interface\\Icons\\INV_Misc_Map_01", color = {0.70,0.49,0.98} },
    { id = "ACHIEVEMENT", label = "Achievement", short = "A", icon = "Interface\\Icons\\Achievement_General", color = {0.94,0.78,0.41} },
    { id = "MOUNT", label = "Mount Hunt", short = "M", icon = "Interface\\Icons\\Ability_Mount_RidingHorse", color = {1.00,0.60,0.25} },
    { id = "OLDRAID", label = "Vecchi Raid", short = "VR", icon = "Interface\\Icons\\INV_Misc_Book_09", color = {0.32,0.86,0.69} },
    { id = "TRANSMOG", label = "Transmog", short = "T", icon = "Interface\\Icons\\INV_Chest_Cloth_17", color = {1.00,0.48,0.79} },
    { id = "PVP", label = "PvP", short = "PvP", icon = "Interface\\Icons\\Achievement_Arena_2v2_1", color = {0.96,0.30,0.30} },
    { id = "ALT", label = "Alt / Leveling", short = "ALT", icon = "Interface\\Icons\\Spell_Holy_WordFortitude", color = {0.49,1.00,0.66} },
    { id = "SOCIAL", label = "Social / Open World", short = "S", icon = "Interface\\Icons\\INV_Misc_Dice_02", color = {0.78,0.78,0.78} },
}

Data.categoryById = {}

Data.keyBands = {
    { id = "ANY", label = "Qualsiasi livello" },
    { id = "LOW", label = "+2 - +7" },
    { id = "MID", label = "+8 - +12" },
    { id = "HIGH", label = "+13 - +15" },
    { id = "PUSH", label = "+16 o superiore" },
    { id = "OWN", label = "La mia chiave" },
}

Data.durations = {
    { id = "30", label = "30 minuti", seconds = 1800 },
    { id = "60", label = "1 ora", seconds = 3600 },
    { id = "90", label = "1 ora e mezza", seconds = 5400 },
    { id = "120", label = "2 ore", seconds = 7200 },
    { id = "180", label = "3 ore", seconds = 10800 },
}

Data.targetSizes = {
    { id = "2", label = "2 persone", value = 2 },
    { id = "3", label = "3 persone", value = 3 },
    { id = "4", label = "4 persone", value = 4 },
    { id = "5", label = "5 persone", value = 5 },
    { id = "10", label = "10 persone", value = 10 },
    { id = "20", label = "20 persone", value = 20 },
}

Data.roles = {
    { id = "ANY", label = "Qualsiasi ruolo" },
    { id = "TANK", label = "Serve Tank" },
    { id = "HEALER", label = "Serve Healer" },
    { id = "DPS", label = "Servono DPS" },
}

Data.presets = {
    MPLUS = {
        { id="vault_chill", label="Vault & Chill", title="Vault & Chill", description="Chiavi senza ansia per riempire la vault. Anche +12 o meno va benissimo: lo scopo e giocare insieme." },
        { id="season2_tour", label="Tour Season 2", title="Tour Season 2", description="Giro della rotazione attuale: Altar of Fangs, Murder Row, Den of Nalorakk, The Blinding Vale, Voidscar Arena, Kings' Rest, Ruby Life Pools e Temple of Sethraliss." },
        { id="legacy_pool", label="Legacy in Season 2", title="Legacy Keys", description="Facciamo una delle tre returning: Kings' Rest, Ruby Life Pools o Temple of Sethraliss." },
        { id="no_pug", label="No Pug: tavolo pieno", title="No Pug", description="Cinque Blackjack, zero pug. La chiave conta meno della compagnia." },
        { id="plus12_club", label="Club della +12", title="Club della +12", description="Una +12 e perfetta: niente gara a chi ha la key piu alta, solo una run fatta bene con la gilda." },
        { id="low_stakes", label="Low Stakes", title="Low Stakes", description="Chiavi basse per alt, offspec, prove, route e risate. Vietato vergognarsi del livello." },
        { id="alt_keys", label="Chiavi per alt", title="Alt Keys", description="Chiavi tranquille per alt, offspec o personaggi rimasti indietro." },
        { id="mentor", label="Mentor Run", title="Mentor Run", description="Portiamo qualcuno che gioca poco M+ e gli diamo una mano con route, pull e meccaniche." },
        { id="roulette", label="Roulette di spec", title="Spec Roulette", description="Se possibile ognuno entra con una spec diversa dal solito. Il timer e secondario, il caos e garantito." },
        { id="three_maps", label="Giro del tavolo", title="Giro del tavolo", description="Tre dungeon diversi, niente spam della stessa chiave. Obiettivo: varieta e compagnia." },
        { id="finish_it", label="Non si lascia il tavolo", title="Finche non la chiudiamo", description="Anche se il timer salta, si finisce insieme." },
        { id="clean_table", label="Tavolo pulito", title="Tavolo pulito", description="Proviamo una run pulita: poche morti, call semplici, nessuna corsa alla key piu alta." },
        { id="twentyone", label="Blackjack 21", title="Blackjack 21", description="Fate chiavi di gilda finche la somma dei livelli completati arriva almeno a 21." },
        { id="random_key", label="Dealer's Choice", title="Dealer's Choice", description="Si fa la chiave scelta a caso dal gruppo. Vietato lamentarsi del dungeon uscito." },
    },
    RAID = {
        { id="venomous_abyss", label="The Venomous Abyss", title="Venomous Abyss", description="Serata Season 2 nel raid corrente: progress, reclear o recupero boss con la gilda." },
        { id="alt_raid", label="Alt Raid", title="Alt Raid", description="Serata raid con alt e offspec. Obiettivo: giocare insieme, non fare parse." },
        { id="progress", label="Progress / Recap", title="Raid Progress", description="Gruppo di gilda per progress, recap meccaniche o recupero boss." },
        { id="fun_rule", label="Raid con regola stupida", title="Raid Roulette", description="Ogni boss aggiunge una piccola regola decisa dal gruppo. Solo caos controllato." },
    },
    DELVE = {
        { id="season2_delves", label="Delve Season 2", title="Delve Season 2", description="Ring of Glory, Gnarldor Isle o Venomfall Deeps: facciamole in compagnia invece che da soli." },
        { id="delve_chain", label="Catena di Delve", title="Delve Night", description="Facciamo piu Delve di fila in compagnia, senza trasformarle in una checklist solitaria." },
        { id="delve_alt", label="Delve per alt", title="Delve per Alt", description="Gear e compagnia per personaggi secondari." },
    },
    ACHIEVEMENT = {
        { id="glory", label="Glory Run", title="Glory Run", description="Scegliamo un meta-achievement e togliamo piu obiettivi possibili dalla lista." },
        { id="roulette_ach", label="Achievement Roulette", title="Achievement Roulette", description="Si sceglie un vecchio raid e si parte dal primo achievement che manca a qualcuno." },
        { id="firelands", label="Firelands Glory", title="Firelands Glory", description="Una serata dedicata agli achievement di Firelands. Il piano puo essere discutibile, la mount no." },
    },
    MOUNT = {
        { id="mount_target", label="Una mount, una missione", title="Mount Hunt", description="Una mount target, 45-60 minuti di tentativi insieme." },
        { id="mount_roulette", label="Mount Roulette", title="Mount Roulette", description="Ognuno propone una mount: /roll e si va tutti sul target vincitore." },
        { id="legacy_mounts", label="Vecchie raid mount", title="Legacy Mount Run", description="Giro vecchi raid per mount e collezionabili. Si resta insieme fino alla fine del giro." },
    },
    OLDRAID = {
        { id="legacy_glory", label="Glory vecchio raid", title="Glory Old School", description="Scegliamo un Glory di una vecchia espansione e lavoriamo sugli achievement mancanti." },
        { id="speed_memory", label="Speedrun a memoria", title="Vecchio Raid a Memoria", description="Niente guida: si entra e si vede quanto ricordiamo davvero." },
        { id="naked", label="Naked-ish Run", title="Nude Run", description="Equip o transmog assurdo concordato dal gruppo. L'importante e la serata." },
        { id="nostalgia", label="Nostalgia Run", title="Nostalgia Run", description="Ulduar, Icecrown, Firelands o qualunque vecchio raid scelto dal tavolo." },
    },
    TRANSMOG = {
        { id="theme", label="Tema della serata", title="Fashion Police", description="Tema scelto dal /roll piu basso; alla fine si vota il transmog piu criminale." },
        { id="farm", label="Farm set", title="Transmog Farm", description="Giro mirato per set e pezzi mancanti, con trade tra membri quando possibile." },
    },
    PVP = {
        { id="bg_chill", label="Battleground chill", title="BG di Gilda", description="Battleground in gruppo senza pretese. Call, risate e focus target discutibili." },
        { id="arena_learn", label="Arena learning", title="Arena Learning", description="Sessione per provare comp, macro e comunicazione senza pressione." },
    },
    ALT = {
        { id="level_chain", label="Leveling insieme", title="Alt Express", description="Quest, dungeon o world content con alt. Si resta insieme invece di sparire nelle code." },
        { id="fresh_alt", label="Fresh max level / gearing", title="Recupero Alt", description="Aiutiamo uno o piu alt a recuperare gear e contenuti base." },
    },
    SOCIAL = {
        { id="coiled_isle", label="Coiled Isle", title="Coiled Isle Night", description="Curse Surge, rare, Vaults of Atal'Utek, pesca o attivita di zona con la gilda." },
        { id="anything", label="Mi sto annoiando", title="Mi sto annoiando", description="Non ho un piano: chi si unisce decide cosa facciamo." },
        { id="mentor_social", label="Gioca con qualcuno di nuovo", title="Mescola il Tavolo", description="Invita qualcuno con cui giochi poco e fate una qualunque attivita insieme." },
        { id="world", label="Open World", title="Giro Open World", description="Rare, world quest, collezionabili o semplicemente due chiacchiere mentre si gira." },
    },
}

Data.challengePool = {
    -- MYTHIC+ - tutte verificate dal completamento reale della chiave.
    { id="mplus_first", group="MPLUS", tracking="auto", title="Prima mano", description="Completa 1 Mythic+ con almeno 3 Blackjack.", mode="stat", key="mplusGuildRuns", goal=1, reward=8 },
    { id="mplus_low_3", group="MPLUS", tracking="auto", title="La +12 va benissimo", description="Completa 3 Mythic+ di gilda di livello 12 o inferiore.", mode="stat", key="mplusLowGuildRuns", goal=3, reward=20 },
    { id="mplus_low_5", group="MPLUS", tracking="auto", title="Low Stakes Club", description="Completa 5 Mythic+ di gilda di livello 12 o inferiore. La key bassa vale quanto la compagnia.", mode="stat", key="mplusLowGuildRuns", goal=5, reward=28 },
    { id="mplus_full_2", group="MPLUS", tracking="auto", title="Tavolo pieno", description="Completa 2 Mythic+ con 5 membri Blackjack, senza pug.", mode="stat", key="mplusFullGuildRuns", goal=2, reward=24 },
    { id="mplus_maps_4", group="MPLUS", tracking="auto", title="Giro del tavolo", description="Completa 4 dungeon Mythic+ diversi con almeno 3 membri di gilda.", mode="set", key="mplusMaps", goal=4, reward=22 },
    { id="mplus_maps_8", group="MPLUS", tracking="auto", title="Tour completo", description="Completa tutti gli 8 dungeon della rotazione Mythic+ corrente con la gilda.", mode="set", key="mplusMaps", goal=8, reward=42 },
    { id="mplus_guildies_8", group="MPLUS", tracking="auto", title="Mescola le carte", description="Completa M+ con 8 compagni Blackjack diversi nella stessa settimana.", mode="set", key="mplusGuildmates", goal=8, reward=24 },
    { id="mplus_21", group="MPLUS", tracking="auto", title="Blackjack 21", description="Accumula 21 livelli di chiave completati in M+ di gilda. Tre +7 vanno benissimo.", mode="stat", key="mplusLevelSum", goal=21, reward=21 },
    { id="mplus_50", group="MPLUS", tracking="auto", title="Cinquanta sul tavolo", description="Accumula 50 livelli di chiave completati con la gilda. Non devono essere chiavi alte.", mode="stat", key="mplusLevelSum", goal=50, reward=28 },
    { id="mplus_finish", group="MPLUS", tracking="auto", title="Non si lascia il tavolo", description="Completa una M+ di gilda anche fuori tempo.", mode="stat", key="mplusOutOfTimeGuildRuns", goal=1, reward=14 },
    { id="mplus_clean", group="MPLUS", tracking="auto", title="Tavolo pulito", description="Completa una M+ di gilda con 0 morti quando il client rende disponibile il dato.", mode="stat", key="mplusZeroDeathGuildRuns", goal=1, reward=28 },
    { id="mplus_timed_3", group="MPLUS", tracking="auto", title="Tre mani pulite", description="Completa in tempo 3 Mythic+ con almeno 3 Blackjack.", mode="stat", key="mplusTimedGuildRuns", goal=3, reward=24 },
    { id="mplus_exact12", group="MPLUS", tracking="auto", title="Dodici secco", description="Completa una Mythic+ esattamente di livello 12 con almeno 3 Blackjack.", mode="stat", key="mplusExact12GuildRuns", goal=1, reward=16 },
    { id="mplus_odd_3", group="MPLUS", tracking="auto", title="Carte dispari", description="Completa 3 Mythic+ di gilda con livello dispari.", mode="stat", key="mplusOddGuildRuns", goal=3, reward=18 },
    { id="mplus_even_3", group="MPLUS", tracking="auto", title="Carte pari", description="Completa 3 Mythic+ di gilda con livello pari.", mode="stat", key="mplusEvenGuildRuns", goal=3, reward=18 },
    { id="mplus_five", group="MPLUS", tracking="auto", title="Cinque mani", description="Completa 5 Mythic+ con almeno 3 Blackjack, a qualunque livello.", mode="stat", key="mplusGuildRuns", goal=5, reward=26 },
    { id="mplus_eight", group="MPLUS", tracking="auto", title="Serata lunga", description="Completa 8 Mythic+ di gilda nella settimana. Il livello non conta.", mode="stat", key="mplusGuildRuns", goal=8, reward=36 },
    { id="mplus_twelve", group="MPLUS", tracking="auto", title="Mazzo completo", description="Completa 12 Mythic+ di gilda nella settimana, senza requisiti sul livello della chiave.", mode="stat", key="mplusGuildRuns", goal=12, reward=48 },

    -- SEASON 2 - raid corrente, pool M+ corrente e Delve.
    { id="season_mplus_5maps", group="SEASON", tracking="auto", title="Season 2 Explorer", description="Completa 5 dungeon diversi della rotazione Mythic+ Season 2 con la gilda.", mode="set", key="mplusMaps", goal=5, reward=24 },
    { id="season_abyss_1", group="SEASON", tracking="auto", title="Primo morso", description="Sconfiggi 1 boss di The Venomous Abyss con almeno 8 Blackjack.", mode="stat", key="currentRaidBosses", goal=1, reward=10 },
    { id="season_abyss_4", group="SEASON", tracking="auto", title="Venomous Abyss: prima meta", description="Sconfiggi 4 boss diversi di The Venomous Abyss con almeno 8 Blackjack.", mode="set", key="currentRaidBossIds", goal=4, reward=26 },
    { id="season_abyss_8", group="SEASON", tracking="auto", title="Venomous Abyss: tavolo completo", description="Sconfiggi tutti gli 8 boss diversi di The Venomous Abyss nella settimana con la gilda.", mode="set", key="currentRaidBossIds", goal=8, reward=44 },
    { id="season_abyss_days", group="SEASON", tracking="auto", title="Due discese nell'Abisso", description="Sconfiggi almeno un boss di The Venomous Abyss in 2 giorni diversi della stessa settimana.", mode="set", key="currentRaidDays", goal=2, reward=22 },
    { id="season_delve_1", group="SEASON", tracking="auto", title="Delve Company", description="Completa 1 Delve con almeno un altro Blackjack.", mode="stat", key="delveGuildRuns", goal=1, reward=8 },
    { id="season_delves_3", group="SEASON", tracking="auto", title="Tre Delve al tavolo", description="Completa 3 Delve con almeno un altro Blackjack.", mode="stat", key="delveGuildRuns", goal=3, reward=18 },
    { id="season_delves_variety", group="SEASON", tracking="auto", title="Tre porte, stesso tavolo", description="Completa 3 Delve differenti con almeno un altro Blackjack.", mode="set", key="delveInstances", goal=3, reward=24 },

    -- RAID - qualsiasi raid affrontato con un vero gruppo di gilda.
    { id="raid_boss_5", group="RAID", tracking="auto", title="Serata di gilda", description="Sconfiggi 5 boss raid con almeno 8 Blackjack presenti.", mode="stat", key="guildRaidBosses", goal=5, reward=20 },
    { id="raid_boss_10", group="RAID", tracking="auto", title="Doppia puntata", description="Sconfiggi 10 boss raid con almeno 8 Blackjack nella settimana.", mode="stat", key="guildRaidBosses", goal=10, reward=32 },
    { id="raid_unique_8", group="RAID", tracking="auto", title="Otto facce del tavolo", description="Sconfiggi 8 boss raid diversi con almeno 8 Blackjack.", mode="set", key="guildRaidBossIds", goal=8, reward=30 },
    { id="raid_people_12", group="RAID", tracking="auto", title="Facce conosciute", description="Gioca raid tracciati con 12 compagni Blackjack diversi.", mode="set", key="raidGuildmates", goal=12, reward=24 },
    { id="raid_two_nights", group="RAID", tracking="auto", title="Due sere al tavolo", description="Sconfiggi almeno un boss raid di gilda in 2 giorni diversi della stessa settimana.", mode="set", key="raidDays", goal=2, reward=18 },
    { id="raid_instances_2", group="RAID", tracking="auto", title="Cambio sala", description="Sconfiggi boss in 2 raid differenti con almeno 8 Blackjack.", mode="set", key="raidInstances", goal=2, reward=20 },

    -- DUNGEON NON-M+ - normale, eroico, mitico 0 e vecchi dungeon.
    { id="dungeon_boss_5", group="DUNGEON", tracking="auto", title="Dungeon Night", description="Sconfiggi 5 boss in dungeon non-M+ con almeno 3 Blackjack.", mode="stat", key="guildDungeonBosses", goal=5, reward=14 },
    { id="dungeon_boss_10", group="DUNGEON", tracking="auto", title="Dieci boss, zero finder", description="Sconfiggi 10 boss in dungeon non-M+ con almeno 3 Blackjack.", mode="stat", key="guildDungeonBosses", goal=10, reward=22 },
    { id="dungeon_instances_3", group="DUNGEON", tracking="auto", title="Tour dei dungeon", description="Affronta boss in 3 dungeon non-M+ differenti con almeno 3 Blackjack.", mode="set", key="dungeonInstances", goal=3, reward=18 },
    { id="dungeon_full_5", group="DUNGEON", tracking="auto", title="Cinque sedie occupate", description="Sconfiggi 5 boss di dungeon con un gruppo formato da 5 Blackjack.", mode="stat", key="fullGuildDungeonBosses", goal=5, reward=20 },

    -- LEGACY - qualunque raid diverso dal raid Season 2 corrente.
    { id="legacy_boss_5", group="LEGACY", tracking="auto", title="Macchina del tempo", description="Sconfiggi 5 boss in vecchi raid con almeno 3 Blackjack.", mode="stat", key="legacyRaidBosses", goal=5, reward=14 },
    { id="legacy_boss_10", group="LEGACY", tracking="auto", title="Archeologi del wipe", description="Sconfiggi 10 boss in vecchi raid con almeno 3 Blackjack.", mode="stat", key="legacyRaidBosses", goal=10, reward=22 },
    { id="legacy_boss_20", group="LEGACY", tracking="auto", title="Museo aperto fino a tardi", description="Sconfiggi 20 boss in vecchi raid con almeno 3 Blackjack.", mode="stat", key="legacyRaidBosses", goal=20, reward=34 },
    { id="legacy_raids_2", group="LEGACY", tracking="auto", title="Due epoche", description="Sconfiggi boss in 2 vecchi raid differenti con almeno 3 Blackjack.", mode="set", key="legacyRaidInstances", goal=2, reward=18 },
    { id="legacy_raids_3", group="LEGACY", tracking="auto", title="Viaggio nel tempo", description="Sconfiggi boss in 3 vecchi raid differenti con almeno 3 Blackjack.", mode="set", key="legacyRaidInstances", goal=3, reward=26 },
    { id="legacy_glory", group="LEGACY", tracking="auto", title="Glory o morte", description="Ottieni un achievement mentre sei in un vecchio raid con almeno 3 Blackjack.", mode="stat", key="legacyAchievements", goal=1, reward=18 },
    { id="legacy_mount", group="LEGACY", tracking="auto", title="Cacciatori di pixel", description="Aggiungi una nuova mount alla collezione mentre sei in un vecchio raid con almeno 3 Blackjack.", mode="stat", key="legacyNewMounts", goal=1, reward=24 },

    -- PVP - completamenti reali del match con gildani nel gruppo.
    { id="pvp_match_1", group="PVP", tracking="auto", title="Cambio tavolo", description="Completa 1 match PvP con almeno un altro Blackjack.", mode="stat", key="guildPvPMatches", goal=1, reward=8 },
    { id="pvp_match_3", group="PVP", tracking="auto", title="Tre mani contro il mondo", description="Completa 3 match PvP con almeno un altro Blackjack.", mode="stat", key="guildPvPMatches", goal=3, reward=16 },
    { id="pvp_match_5", group="PVP", tracking="auto", title="Dealer da battaglia", description="Completa 5 match PvP con almeno un altro Blackjack.", mode="stat", key="guildPvPMatches", goal=5, reward=24 },
    { id="pvp_maps_3", group="PVP", tracking="auto", title="Tre tavoli PvP", description="Completa match PvP in 3 istanze o mappe differenti con almeno un altro Blackjack.", mode="set", key="pvpInstances", goal=3, reward=20 },

    -- CRAFTING DI GILDA - verificato dalla risposta di fulfillment dell'ordine Guild.
    { id="craft_guild_1", group="CRAFTING", tracking="auto", title="Made in Blackjack", description="Completa 1 ordine di crafting di tipo Guild come crafter.", mode="stat", key="guildCraftsCompleted", goal=1, reward=10 },
    { id="craft_guild_3", group="CRAFTING", tracking="auto", title="Artigiano del tavolo", description="Completa 3 ordini di crafting di tipo Guild nella stessa settimana.", mode="stat", key="guildCraftsCompleted", goal=3, reward=22 },
    { id="craft_guild_5", group="CRAFTING", tracking="auto", title="Officina Blackjack", description="Completa 5 ordini di crafting Guild nella stessa settimana.", mode="stat", key="guildCraftsCompleted", goal=5, reward=32 },

    -- COMMUNITY - progressi derivati da attivita reali, mai da checkbox manuali.
    { id="community_guildmates_10", group="COMMUNITY", tracking="auto", title="Conosci il tavolo", description="Gioca in contenuti tracciati con 10 compagni Blackjack diversi.", mode="set", key="allGuildmates", goal=10, reward=24 },
    { id="community_guildmates_15", group="COMMUNITY", tracking="auto", title="Quindici volti familiari", description="Gioca in contenuti tracciati con 15 compagni Blackjack diversi nella settimana.", mode="set", key="allGuildmates", goal=15, reward=34 },
    { id="community_ach_1", group="COMMUNITY", tracking="auto", title="Pop!", description="Ottieni un achievement mentre sei in gruppo con almeno un altro Blackjack.", mode="stat", key="guildAchievements", goal=1, reward=10 },
    { id="community_ach_3", group="COMMUNITY", tracking="auto", title="Serata achievement", description="Ottieni 3 achievement mentre sei in gruppo con la gilda.", mode="stat", key="guildAchievements", goal=3, reward=18 },
    { id="community_ach_unique_5", group="COMMUNITY", tracking="auto", title="Cinque ding", description="Ottieni 5 achievement diversi mentre sei in gruppo con la gilda.", mode="set", key="guildAchievementIds", goal=5, reward=24 },
    { id="community_variety_3", group="COMMUNITY", tracking="auto", title="Mescola il tavolo", description="Completa attivita di gilda in 3 tipi di contenuto diversi tra M+, raid, legacy, dungeon, Delve, PvP, achievement e Crafting.", mode="set", key="contentTypes", goal=3, reward=18 },
    { id="community_variety_5", group="COMMUNITY", tracking="auto", title="Tutto il casino", description="Completa attivita di gilda in 5 tipi di contenuto diversi nella stessa settimana, Crafting incluso.", mode="set", key="contentTypes", goal=5, reward=30 },
    { id="community_mount", group="COMMUNITY", tracking="auto", title="Una sedia in piu in scuderia", description="Aggiungi una nuova mount alla collezione mentre sei in gruppo con almeno un altro Blackjack.", mode="stat", key="guildNewMounts", goal=1, reward=18 },
}

Data.rewards = {
    { id="starter", type="title", price=0, title="Credere nel piano", subtitle="Titolo base Blackjack." },
    { id="card_hidden", type="title", price=30, title="Carta Coperta", subtitle="Compare sempre quando serve." },
    { id="plus12_legend", type="title", price=40, title="La +12 Basta", subtitle="Non serve una +25 per divertirsi." },
    { id="low_key", type="title", price=45, title="Low Key Legend", subtitle="Poche pretese, tante run." },
    { id="out_of_time", type="title", price=50, title="Fuori Tempo ma Felici", subtitle="Il timer e morto, il gruppo no." },
    { id="dealer_quartiere", type="title", price=60, title="Dealer di Quartiere", subtitle="Organizza il caos con sorprendente calma." },
    { id="summon", type="title", price=65, title="Re del Summon", subtitle="Ha salvato piu viaggi di un portale." },
    { id="lag", type="title", price=65, title="Colpa del Lag", subtitle="Difesa ufficiale in ogni circostanza." },
    { id="not_me", type="title", price=70, title="Non Ero Io", subtitle="Mai visto quella pozza prima." },
    { id="full_table", type="title", price=75, title="Tavolo Pieno", subtitle="Cinque Blackjack, zero pug." },
    { id="floor", type="title", price=80, title="Pavimentista Certificato", subtitle="Il pavimento va studiato da vicino." },
    { id="glory_addict", type="title", price=85, title="Glory Addict", subtitle="Ancora un achievement e poi smettiamo." },
    { id="pixel_hunter", type="title", price=90, title="Cacciatore di Pixel", subtitle="Mount, pet, toy: tutto fa curriculum." },
    { id="transmog_crime", type="title", price=95, title="Transmog Criminale", subtitle="La Fashion Police ha aperto un fascicolo." },
    { id="alt_addict", type="title", price=100, title="Alt Addict", subtitle="Il main e solo un'opinione." },
    { id="old_school", type="title", price=105, title="Vecchia Scuola", subtitle="Conosce ancora la strada per Ulduar." },
    { id="no_pug", type="title", price=110, title="Pug? Mai Sentito", subtitle="La compagnia prima del finder." },
    { id="social_main", type="title", price=115, title="Social Main", subtitle="La vera spec e stare in compagnia." },
    { id="dealers_choice", type="title", price=120, title="Dealer's Choice", subtitle="Accetta il dungeon che esce." },
    { id="ace_spades", type="title", price=135, title="Ace of Spades", subtitle="Un posto al tavolo principale." },
    { id="coiled_regular", type="title", price=140, title="Coiled Regular", subtitle="Ha gia il tavolo prenotato sulla Coiled Isle." },
    { id="abyss_tourist", type="title", price=145, title="Abyss Tourist", subtitle="Ha visto abbastanza veleno per una stagione." },
    { id="disciple", type="title", price=160, title="Discepolo del Piano", subtitle="Ha smesso di chiedere perche." },
    { id="all_in", type="title", price=175, title="All In", subtitle="Quando c'e da fare gruppo, c'e." },
    { id="natural21", type="title", price=190, title="21 Naturale", subtitle="La mano perfetta." },
    { id="blackjack", type="title", price=220, title="Blackjack", subtitle="Ventuno. Fine della discussione." },

    { id="badge_spade", type="badge", price=35, title="Badge: Picche", subtitle="Badge Passport dedicato al simbolo Blackjack." },
    { id="badge_chip", type="badge", price=55, title="Badge: Fiche Verde", subtitle="Per chi accumula fiches senza perderle tutte." },
    { id="badge_dealer", type="badge", price=75, title="Badge: Dealer", subtitle="Per chi apre spesso il tavolo agli altri." },
    { id="badge_oldschool", type="badge", price=85, title="Badge: Old School", subtitle="Per gli archeologi del vecchio contenuto." },
    { id="badge_mplus", type="badge", price=95, title="Badge: M+ Crew", subtitle="Per chi considera la key un pretesto per stare insieme." },
    { id="badge_raid", type="badge", price=95, title="Badge: Raid Night", subtitle="Per i clienti abituali del raid." },

    { id="weekly_gold_250", type="weekly_gold", price=75, gold=250, title="Busta del Dealer - 250g", subtitle="Una volta per reset: spendi fiches e crea una richiesta da 250g nella Cassa Blackjack. Pagamento verificabile dagli officer e, se il rank lo consente, dalla banca di gilda." },
}

Data.rewardById = {}

function Data:Initialize()
    wipe(self.categoryById)
    wipe(self.rewardById)
    for i = 1, #self.categories do
        self.categoryById[self.categories[i].id] = self.categories[i]
    end
    for i = 1, #self.rewards do
        self.rewardById[self.rewards[i].id] = self.rewards[i]
    end
end

function Data:GetCategory(id)
    return self.categoryById[id] or self.categoryById.SOCIAL
end

function Data:GetPresets(category)
    return self.presets[category] or self.presets.SOCIAL
end

function Data:GetPreset(category, presetId)
    local list = self:GetPresets(category)
    for i = 1, #list do if list[i].id == presetId then return list[i] end end
    return list[1]
end

function Data:GetDuration(id)
    for i = 1, #self.durations do if self.durations[i].id == id then return self.durations[i] end end
    return self.durations[2]
end

function Data:GetTarget(id)
    for i = 1, #self.targetSizes do if self.targetSizes[i].id == id then return self.targetSizes[i] end end
    return self.targetSizes[4]
end

function Data:GetReward(id)
    return self.rewardById[id] or self.rewardById.starter
end

function Data:GetActiveChallenges()
    local out = {}
    for i = 1, #self.challengePool do out[#out + 1] = self.challengePool[i] end
    return out
end
