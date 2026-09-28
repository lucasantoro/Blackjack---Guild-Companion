# Verifica rete e permessi — 3.0.11

Eseguire dalla cartella dell'addon:

```text
lua Tests/regression.lua
```

In ambienti con TeX Live: `luatex --luaonly Tests/regression.lua`.
La suite usa API WoW simulate e controlla anche la sintassi di tutti i file Lua elencati nel TOC.

## Difetti riscontrati e correzioni

- `HandleRemoteActivity` sostituiva incondizionatamente il proprietario di un ID esistente. Gli ID precedenti combinavano secondi e soli 12 bit casuali, senza identita del creatore. Ora gli ID includono GUID e contatore persistente e il proprietario non puo essere sostituito da un altro mittente. Questo riproduce un percorso compatibile con la segnalazione; senza log dei due client non dimostra quale pacchetto abbia causato il caso osservato.
- ACTDEL e COUNT erano accettati da qualunque mittente. Ora richiedono il proprietario; le revisioni impediscono regressioni del conteggio. Le cancellazioni restano memorizzate per almeno la durata massima di un'attivita e vengono ripetute dal proprietario, anche quando non ha piu eventi attivi.
- JOIN ripetuti erano ridondanti; ora sono idempotenti. Le iscrizioni vengono riaffermate alla ricezione degli annunci del proprietario. LEAVE viene ripetuto fino alla scadenza dell'attivita, salvo nuova iscrizione.
- Il reset cache cancellava anche attivita proprie e dati utili al recupero crafting. Ora conserva i dati locali e lo storico di completamento, quindi richiede e annuncia lo stato di rete. Le iscrizioni sono separate per personaggio. Le vecchie iscrizioni senza identita del personaggio non vengono attribuite automaticamente.
- Coda massima di 1024 messaggi, deduplicazione dei messaggi identici in attesa, massimo 8 tentativi come nel trasporto precedente. Richieste di sincronizzazione limitate a una per mittente/tipo ogni 10 secondi. Testi attivita in attesa: massimo 256, scadenza 5 minuti. Peer inattivi: 1 giorno; Passport: 30 giorni; riepiloghi: 7 giorni. Ledger e storico finanziario non vengono rimossi.
- PCLEAR conserva una revisione di cancellazione: i vecchi campi Passport non possono riapparire dopo la revoca della condivisione. Riattivare la condivisione genera una revisione superiore.
- Crafting rifiuta annunci che cambiano il proprietario di un ordine gia noto.
- Cassa e laboratorio TEST sono riservati ai gradi 0/1 (GM/vice GM). I permessi sulle note officer non concedono piu accesso amministrativo. Raider mantiene la vista personale per i membri abilitati, mentre nasconde la panoramica di gestione. La perdita del grado chiude le pagine riservate gia aperte e disattiva effettivamente TEST.

## Prova in gioco con due o tre account

1. Installare 3.0.11 su GM e vice GM, quindi fare `/reload` su entrambi. Un terzo account di grado ordinario serve a verificare la UI senza permessi.
2. Creare un'attivita col vice GM, poi una col GM nello stesso momento. Attendere almeno 2 minuti e usare `/bj sync`. Ogni evento deve rimanere sotto le attivita del suo creatore; l'altro account deve vederlo come evento di gilda.
3. Iscriversi, uscire, iscriversi di nuovo. Verificare il conteggio sull'autore, anche dopo `/reload`. Cancellare e ripetere la sincronizzazione: l'evento non deve riapparire.
4. Svuotare la cache mentre un evento proprio e attivo: l'evento e i partecipanti devono restare. Cambiare personaggio e tornare al precedente: le iscrizioni non devono passare all'alt.
5. Sul membro ordinario verificare che Cassa e laboratorio TEST non siano visibili e che `/bj cassa` e `/bj test` non aggirino il controllo. Un Raider deve vedere la propria situazione senza la panoramica amministrativa.
6. Retrocedere un amministratore con Cassa o gestione Raider aperta: dopo l'aggiornamento roster la pagina o i controlli riservati devono sparire.
7. Disattivare e riattivare la condivisione Passport: verificare scomparsa e ricomparsa sull'altro client. Usare `/bj net` su entrambi per rilevare code o invii falliti.

## Limiti della verifica

Questi sono test di logica e sintassi, non un'esecuzione nel client WoW. Restano da verificare layout effettivo, eventi del roster, restrizioni Blizzard e trasporto tra account/realm reali. I messaggi amministrativi Raider continuano a usare il trasporto WHISPER preesistente: questa revisione non ne cambia la disponibilita tra realm.

Il protocollo resta V5: i vecchi client possono leggere gli annunci, ma non ricevono retroattivamente le nuove protezioni. Aggiornare tutti i partecipanti e raccomandato. Il recupero dipende da client online, heartbeat e limiti del canale; non esiste un server persistente o una garanzia di consegna. Un'attivita il cui proprietario e gia stato sovrascritto nei vecchi dati non viene riassegnata automaticamente senza prove attendibili: va ricreata dal proprietario dopo l'aggiornamento.

Nascondere un pannello non rende segreti dati gia trasmessi sul canale di gilda. Questa revisione limita UI e operazioni consentite; non introduce crittografia o un'autorita centrale per l'intero addon.
