BLACKJACK GUILD COMPANION 2.6.0

NOVITA 2.6
- HUD compatto: mostra solo contatore Attivita e Craft finche non premi Apri.
- Pannello espanso scrollabile con tutte le attivita/craft e azioni rapide.
- Direzione di apertura HUD configurabile: basso, alto, destra, sinistra.
- Nuovi tavoli e craft fanno lampeggiare brevemente la barra HUD.
- Reward Shop con area catalogo molto piu ampia e header compatto.

NOVITA 2.5.0 - CRAFTING DI GILDA

- Nuova pagina CRAFTING: gli ordini creati come tipo Guild vengono rilevati automaticamente dopo la conferma di WoW e condivisi ai membri Blackjack con l'addon.
- Per ogni ordine mostra oggetto, proprietario, qualita minima, commissione, reagenti forniti, scadenza, stato e nota del cliente.
- Pulsante "Posso craftarlo": i crafter interessati vengono sincronizzati e il proprietario vede nomi e conteggio.
- Recovery di rete: richiesta CREQ, rebroadcast periodico e ripubblicazione degli interessi.
- Gli ordini chiusi/scaduti vengono spostati nello storico recente.
- Activity HUD ora puo mostrare anche gli ordini Crafting, con icona oggetto e numero di crafter disponibili.
- 3 nuove challenge automatiche: 1, 3 e 5 ordini Guild completati come crafter.
- Il tasto Cassa non dice piu "Apri banca": quando la banca non e fisicamente aperta mostra "Banca non aperta" e spiega il requisito nel tooltip.
- /bj crafting apre direttamente il modulo.


NOVITA 2.3.1

SYNC REWARD / CASSA 2.3.1
- Titolo e badge reali vengono inviati sia come metadata PMETA sia come STYLE leggibile, per maggiore affidabilita.
- In Modalita Test, titolo/badge e Cassa usano una sandbox separata ma possono essere sincronizzati con altri client che hanno la Modalita Test attiva.
- La Busta del Dealer TEST non tocca la Cassa reale e non puo usare la banca di gilda.
- La Cassa reale richiede periodicamente lo stato alla gilda e ritenta automaticamente il broadcast di un nuovo claim.

------------
- Passport V3: sincronizzazione sul canale GUILD invece dei whisper addon. Questo evita il limite dei whisper tra realm non connessi e rende i profili visibili anche nelle gilde cross-realm.
- Il client che entra online provoca un riannuncio leggermente ritardato dei Passport degli altri client Blackjack; selezionare un membro invia comunque una richiesta esplicita di refresh.
- Identita personaggio normalizzata sempre in formato Nome-Realm, con migrazione del Passport locale salvato dalle vecchie versioni.
- Nuova pagina Cassa Blackjack per i reward da 250g: richieste DA PAGARE, stato PAGATO, totale dovuto e storico locale.
- GM/officer possono segnare manualmente un reward come pagato. Lo stato viene sincronizzato alla gilda.
- Aprendo la banca di gilda, gli officer possono usare Verifica banca: l'addon interroga il money log e abbina automaticamente i prelievi da 250g alle richieste aperte.
- Se il rank del giocatore dispone gia del permesso di prelievo gold e il limite residuo e sufficiente, il reward mostra Ritira 250g direttamente mentre la banca e aperta.
- La modalita TEST non crea richieste reali nella Cassa.

BLACKJACK - GUILD COMPANION 2.2.0
==================================

Addon sociale privato della gilda Blackjack - Nemesis EU.
Sito: https://www.blackjackguild.it

INSTALLAZIONE
-------------
1. Estrai la cartella BlackjackGuild in:
   World of Warcraft/_retail_/Interface/AddOns/
2. Fai /reload.
3. Apri con /bj, dal pulsante minimappa oppure dall'AddOn Compartment.

ACCESSO PRIVATO
---------------
L'addon verifica il personaggio in gioco:
- Gilda: Blackjack
- Realm gilda: Nemesis

Se il controllo non passa, UI, tracking, reward e sincronizzazione restano bloccati.
Il controllo viene ripetuto quando cambiano gilda/roster e quando entri nel mondo.

SALVATAGGIO E RESET
-------------------
I dati sono salvati in BlackjackDB (SavedVariables account-wide).

Persistono tra una settimana e l'altra:
- fiches disponibili
- fiches guadagnate in totale
- titoli e badge sbloccati
- claim gold delle settimane precedenti
- Passport dei personaggi
- impostazioni e posizione UI

Si azzerano automaticamente al reset settimanale:
- progressi delle challenge
- statistiche e set settimanali usati dal tracking
- stato RISCUOTI delle challenge della nuova settimana
- disponibilita settimanale della Busta del Dealer da 250g

IMPORTANTE: LE FICHES NON SI AZZERANO AL RESET.

CHALLENGE - SOLO TRACKING AUTOMATICO
------------------------------------
Dalla 2.2.0 non esiste piu nessun sistema di autocertificazione, checkbox,
"Segna fatta", +1 o -1.

La board contiene 58 challenge automatiche divise in:
- Mythic+
- Season 2 / contenuto attuale
- Raid
- Dungeon non-M+
- Legacy / vecchio contenuto
- PvP
- Crafting di gilda
  - Notifica personale al committente quando un ordine Guild viene completato.
  - Il riquadro CRAFT dell HUD resta evidenziato in oro con POSTA N finche l allegato non viene ritirato.
  - Il ritiro viene verificato sulla mailbox: aprire la posta non basta a cancellare la notifica.
- Community

Il progresso viene aggiornato soltanto da eventi reali del client WoW, tra cui:
- completamento Mythic+
- boss raid/dungeon sconfitti
- completamento Delve
- match PvP completati
- achievement ottenuti in gruppo
- nuove mount aggiunte alla collezione mentre sei con la gilda
- ordini Guild completati come crafter

MYTHIC+
-------
Gli obiettivi non ruotano solo attorno alla key piu alta:
- run <= +12
- una +12 esatta
- 5 giocatori di gilda
- dungeon differenti
- chiavi fuori tempo ma concluse
- run senza morti, quando il dato e disponibile
- livelli pari/dispari
- somma livelli 21
- compagni diversi
- 5, 8 e 12 run di gilda
- intera rotazione stagionale

CONTENUTO SEASON 2
------------------
Sono gia presenti attivita/preset e challenge automatiche per:
- The Venomous Abyss
- Delve Season 2
- Season 2 Mythic+ rotation

La rotazione inserita nella build 12.1:
- Altar of Fangs
- Murder Row
- Den of Nalorakk
- The Blinding Vale
- Voidscar Arena
- Kings' Rest
- Ruby Life Pools
- Temple of Sethraliss

REWARD SHOP
-----------
Le challenge completate NON aggiungono fiches automaticamente.
Quando una challenge raggiunge davvero il suo obiettivo compare RISCUOTI.
Premendo RISCUOTI le fiches entrano nel saldo permanente.

Nel Reward Shop:
- ogni reward mostra sempre il proprio costo in fiches
- pulsante VERDE = puoi compiere l'azione adesso
- pulsante GRIGIO = saldo insufficiente, reward gia equipaggiata o claim non disponibile
- le fiches restano tra una settimana e l'altra

Le fiches possono essere spese per:
- titoli Blackjack
- badge Passport
- reward settimanale da 250 gold

BUSTA DEL DEALER - 250 GOLD
---------------------------
- costa 75 fiches
- il costo e sempre visibile accanto al reward
- pulsante verde solo se hai almeno 75 fiches e non l'hai gia riscattata nel reset
- pulsante grigio se non hai abbastanza fiches o l'hai gia riscattata
- si puo riscattare una sola volta per reset settimanale
- il claim viene registrato nelle SavedVariables
- NON genera gold automaticamente

Un addon WoW non crea valuta di gioco. GM/officer devono effettuare il pagamento
manualmente dopo aver verificato il claim.

ADDON COMPARTMENT / ELLESMEREUI
--------------------------------
Il pulsante Blackjack e figlio diretto di Minimap, con nome stabile e dimensione
34x34, quindi puo essere raccolto dal flyout addon di EllesmereUI.

In parallelo Blackjack si registra anche nel compartment Blizzard.

Accessi:
- flyout addon di EllesmereUI: pulsante Blackjack
- AddOn Compartment Blizzard: voce Blackjack - Guild Companion
- click sinistro: finestra principale
- click destro: Activity HUD

COMANDI
-------
/bj
/bj attivita
/bj challenges
/bj rewards
/bj members
/bj settings
/bj hud
/bj sync
/bj net
/bj test
/bj testreset
/bj resetpos
/bj help

MODALITA TEST / LAB
-------------------
La v2.2.3 include una sandbox di test pensata per verificare UI e reward senza
modificare i dati reali. Si attiva da Impostazioni > LAB TEST oppure con /bj test.

Quando e attiva compare MODALITA TEST nell'header.
La sandbox mantiene separati:
- saldo fiches TEST
- challenge completate/riscosse TEST
- titoli e badge sbloccati TEST
- titolo e badge equipaggiati TEST
- claim settimanale Busta del Dealer TEST

Controlli disponibili:
- 5000 fiches: imposta un saldo TEST sufficiente per provare gli acquisti
- Completa tutte: forza localmente tutte le challenge a complete
- Sblocca reward: rende disponibili tutti i titoli e badge nella sandbox
- Reset test: azzera solo la sandbox TEST, compreso il claim 250g simulato

La modalita TEST non modifica fiches, reward, progressi o claim reali e non invia
riepiloghi fittizi agli altri membri. Il claim 250g in TEST non richiede alcun
pagamento reale da parte di GM/officer.

Comandi aggiuntivi:
/bj test
/bj testreset


NOTE
----
La sincronizzazione usa i canali addon di WoW e non un server esterno.
Come per qualunque addon WoW, le SavedVariables sono file locali e possono essere
modificate manualmente fuori dal gioco; l'interfaccia dell'addon, pero, non offre
nessun modo per aggiungere progresso alle challenge a mano.


PASSPORT
--------
Il Blackjack Passport e la scheda sociale del tuo personaggio nell'addon.
Non assegna punteggi e non misura la performance. Serve a far capire agli altri membri:
- chi sei / la tua frase personale
- quali contenuti ti piace fare
- per cosa possono chiederti aiuto
- quali alt usi principalmente
- quale titolo e badge Blackjack hai equipaggiato

Il Passport compare nella pagina Membri e, dalla 2.2.2, anche passando il mouse sui tavoli aperti.
Per modificare il tuo profilo usa il pulsante "Il mio Passport" oppure /bj passport.
I profili degli altri membri sono volutamente in sola lettura.


NOVITA 2.2.6
- Passport: sincronizzazione point-to-point riscritta.
- Quando salvi, la gilda riceve solo la nuova revisione; ogni client richiede poi lo snapshot aggiornato direttamente al proprietario.
- Lo snapshot viene applicato solo quando metadata e tutti e quattro i campi sono arrivati.
- Il destinatario invia un ACK; senza ACK il mittente riprova automaticamente.
- I testi del Passport usano SendAddonMessageLogged in formato plain-text leggibile.
- Le vecchie cache Passport vengono considerate legacy e sostituite da uno snapshot autorevole.
- /bj net mostra anche stato della sincronizzazione Passport e ACK in attesa.

NOVITA 2.2.5
- Sincronizzazione del Messaggio tavolo resa affidabile con ACTTXT logged plain-text.
- Il creatore del tavolo vede i nomi di chi ha aderito.
- Pulsante INV su tavoli propri (pagina Attivita e HUD) per invitare in gruppo i partecipanti che hanno premuto Ci sono.
- INV resta disabilitato quando non ci sono giocatori in attesa o sono gia nel gruppo.


CRAFTING - CICLO VITA ORDINI (v2.5.1)
- Claim, crafting, release/reject e fulfillment aggiornano immediatamente anche la cache locale del crafter.
- Fulfillment sposta l'ordine negli ordini recenti e lo rimuove da pagina Crafting, Home e HUD.
- Gli stati terminali sono ritrasmessi per alcuni minuti e protetti da tombstone per evitare che una copia vecchia venga ripubblicata come attiva.
