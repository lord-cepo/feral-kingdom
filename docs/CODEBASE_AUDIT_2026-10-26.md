# Audit statico di feral-kingdom

Data: 26 ottobre 2026. Stato: proposta da approvare, nessuna modifica al codice.

## Esito

Il debito principale è concentrato nella presentazione, nelle interrogazioni ripetute dello stato e nella manutenzione parallela di regole equivalenti. Non emerge una ragione per riscrivere il sistema di effetti: la separazione tra definizioni, esecuzioni, riferimenti e risoluzione è una base da conservare.

Le priorità consigliate sono: consolidare la logica dei costi; rendere più robusto il caricamento dei salvataggi; ridurre i ricalcoli del controllo e le scansioni della presentazione; eliminare solo i residui realmente inutilizzati. Le ottimizzazioni prestazionali sono opportunità motivate dalla struttura del codice, non rallentamenti misurati.

## Metodo, copertura e limiti

Inventario dell'intero albero `scripts/`, ricerca trasversale di riferimenti in script, scene, test, strumenti e documentazione; lettura mirata delle implementazioni di modello, selezione, contributi, costi, runner, combattimento, salvataggi, board e interfaccia. Confronto con AGENTS.md, FILE_GUIDE, ROADMAP e PROJECT_SIZE. Ricerca automatica di corpi di funzione identici, ignorando commenti e righe vuote, con almeno quattro righe significative.

Questo è un audit statico: non sono stati avviati Godot, test, profiler o benchmark. Non certifica l'assenza di altri difetti, né costituisce una verifica esaustiva di tutte le interazioni delle carte. Asset grafici, foglio cards.xlsx e strumenti di esportazione non sono stati sottoposti a verifica funzionale o confronto binario. Nessuna ricerca web necessaria: le conclusioni riguardano il contenuto locale.

La cartella corrente non contiene un repository Git utilizzabile: `git status` restituisce «not a git repository». Non è quindi disponibile un confronto con una revisione iniziale. Durante l'audit è stato creato esclusivamente questo report.

### Inventario rilevato

| Voce | Quantità |
| --- | ---: |
| Script applicativi sotto scripts/ | 74 |
| Righe fisiche applicative, inclusi commenti e righe vuote | 12.943 |
| Dichiarazioni di funzioni nominate, incluse classi annidate | 900 |
| Script di test | 8 |
| Righe negli script di test | 2.261 |
| Funzioni senza una riga `##` immediatamente precedente | 75 |

L'ultimo conteggio è un indicatore automatico da verificare manualmente: non misura la qualità dei contratti e può includere convenzioni particolari. Non va interpretato come elenco definitivo di 75 violazioni.

| File più estesi | Righe |
| --- | ---: |
| scripts/ui/local_match_controller.gd | 1.460 |
| scripts/board/board.gd | 1.232 |
| scripts/board/hex_cell.gd | 1.088 |
| scripts/combat/combat_resolver.gd | 926 |
| scripts/ui/effect_text.gd | 581 |
| scripts/catalogue/card_catalogue.gd | 476 |
| scripts/runtime/match_snapshot.gd | 430 |

La lunghezza segnala concentrazione di responsabilità; da sola non prova cattiva qualità. I tre maggiori file UI/board totalizzano 3.780 righe, circa il 29% degli script applicativi.

## Rilievi e interventi proposti

Priorità: P1 = prima tranche consigliata; P2 = consolidamento successivo; P3 = pulizia o intervento subordinato a misure. Non sono stati confermati difetti P0 bloccanti tramite esecuzione.

### A01 — Regole cumulative dei costi mantenute in due punti — P1

**Evidenza:** `scripts/runtime/rules_runner.gd`, `_cost_choices_available()`; `scripts/effects/cost_payment.gd:8`, `commit()`.

Entrambi mantengono registri ombra per decrementi, vita e attività. Il runner usa un registro con chiavi `life:<id>`, il pagamento un dizionario vita separato. Inoltre il pagamento aggiorna il registro Stun per self_stun, mentre la ricerca di disponibilità registra soltanto l'attività. La differenza è reale; non basta da sola a dimostrare un errore nelle carte attuali.

**Impatto:** una nuova famiglia di costo può apparire disponibile e fallire al pagamento, oppure venire rifiutata dalla previsione. Le modifiche richiedono aggiornamenti coordinati.

**Proposta:** estrarre una sola operazione di preflight non mutante su un registro esplicito, usata sia dall'esplorazione delle scelte sia dal commit. Conservare la scelta combinatoria nel runner e la mutazione nel pagamento. Rifiutare i costi non supportati in entrambi i percorsi.

**Rischio:** alto, perché tocca atomicità e ordine dei followup. Verifica futura: costi cumulativi, stessa attività due volte, vita a zero, scelte alternative e fallimento senza mutazione.

### A02 — Validazione dei salvataggi incompleta prima della mutazione — P1

**Evidenza:** `scripts/runtime/match_snapshot.gd:104`, `_is_compatible_snapshot()`; `:171`, `_apply_state()`; `:359`, `_restore_combat_records()`.

Il validatore controlla identità del roster, alcuni valori e contenitori, ma per numerosi record di combattimento verifica soltanto che siano dizionari. La ricostruzione accede poi direttamente a campi come `saved.source`, `saved.hex`, `saved.damage`. Anche stato/posizione delle unità e risorse dei giocatori non ricevono una validazione completa dei rispettivi domini. Il ripristino modifica Match progressivamente.

**Impatto:** un JSON incompleto o incoerente può superare il primo filtro e fallire o introdurre stato non valido durante il caricamento. Il commento che promette protezione da sovrascritture parziali è più forte della validazione effettiva.

**Proposta:** validare tutti i campi obbligatori, tipi, intervalli e riferimenti; ricostruire record temporanei prima di applicarli. Distinguere migrazione del formato da validazione dello stato.

**Rischio:** medio/alto. Verifica futura: campi mancanti, ID invalidi, stati non ammessi, risorse negative, compatibilità v1/v2 e rifiuto senza mutare Match.

### A03 — Controllo regionale ricalcolato per ogni esagono — P1

**Evidenza:** `scripts/runtime/control_resolver.gd:12`, `strength()`; `:28`, `region_owner()`; `:38`, `refresh()`.

Ogni refresh visita tutta la mappa e per ciascuna tessera calcola due volte la forza regionale, scorrendo l'esercito. Molte tessere appartengono alla stessa regione. Anche il bonus fisico e i filtri di controllo interrogano nuovamente il calcolo live.

**Impatto:** il refresh completo costa O(H × U), pur producendo un risultato condiviso fra esagoni della stessa regione.

**Proposta:** aggregare forza e proprietario una volta per chiave regionale durante un refresh, poi distribuirli alla mappa. Per letture live mantenere inizialmente il comportamento attuale; introdurre cache persistenti soltanto con invalidazione dimostrabile.

**Rischio:** medio. Preservare vita corrente, control_bonus, pareggio di casa, neutralità e partecipanti Bash. Il +1 fisico non deve entrare nella forza regionale.

### A04 — Refresh completo e ridondante di board/controllo — P1

**Evidenza:** `scripts/board/board.gd:863`, `refresh_board()`; `:1024`, `_on_selection_changed()`; `scripts/runtime/match.gd`, deployment/defeat; `scripts/board/hex_cell.gd:146`, `refresh()`.

Match aggiorna già il controllo in diverse mutazioni; il refresh grafico lo ricalcola ancora. Ogni modifica della selezione richiama `refresh()` su tutte le celle, ricostruendo testo e alcune strutture di presentazione anche quando cambia soltanto l'evidenziazione. Esistono già preservazioni utili per BoardCharacter e Bash, da conservare.

**Proposta:** separare aggiornamento dei candidati da aggiornamento dei contenuti; identificare celle e dati effettivamente cambiati. Centralizzare la responsabilità del ricalcolo del controllo senza trasferire regole alla UI.

**Rischio:** alto per animazioni e input. Verifica futura: scelta UNIT su esagono condiviso, cambio selezione, ingresso/uscita Bash e continuità delle animazioni.

### A05 — Controllo globale delle animazioni ripetuto dalle celle — P1

**Evidenza:** `scripts/board/hex_cell.gd:391`, `_process()`; `:939`, `_update_control_color()`; `scripts/board/board.gd:1200`, `_phase_presentation_busy()`.

Ogni cella con un cambio colore pendente interroga il board; la query globale visita celle, figure e nodi di feedback. Con C celle in attesa, la stessa scansione globale può ripetersi C volte nello stesso fotogramma.

**Proposta:** calcolare la disponibilità della presentazione una volta per aggiornamento del board, oppure notificare alle celle quando la coda finita si libera. Preservare una query autorevole per le continuazioni del runner.

**Rischio:** alto sul timing. Sleeping, counter persistenti, ambience e replay non devono diventare bloccanti.

### A06 — Derivazioni dei contributi ripetute per ogni getter — P2

**Evidenza:** `scripts/model/unit_info.gd:239`, `has_effective_flag()`; `:258`, `effective_action_values()`; `:323`, `state_modifiers()`; `:341`, `modifier_breakdown()`; `scripts/effects/continuous_effect.gd:51`, `applies_to()`.

Le letture attraversano sorgenti e aure; l'applicabilità risolve nuovamente il selettore dei destinatari. Getter separati fisico/magico ricostruiscono l'intero modifier; alcuni formatter leggono lo stesso getter più volte. Il costo dipende da unità, aure, candidati e frequenza di lettura.

**Proposta:** prima riusare i risultati all'interno della stessa operazione di rendering/query. Valutare poi un risultato derivato comune per destinatario e stato. Una cache globale richiederebbe invalidazione per vita, posizione, proprietà, proprietà delle unità, copie, grant e risorse del giocatore.

**Rischio:** alto per cache persistenti, basso per riuso locale. Nessun contributo deve essere memorizzato come contatore o produrre eventi.

### A07 — Ricerca coordinate e occupanti con scansioni complete — P2

**Evidenza:** `scripts/runtime/match.gd`, `occupants()`; `scripts/combat/combat_resolver.gd:662`, `_hex_at_coordinate()`; `:868`, `walk_path()`; `scripts/board/board.gd:996`, `_hex_id_at()`.

Coordinate→esagono è cercato linearmente in più sottosistemi. La BFS di movimento ripete la ricerca per vicini e predecessori, oltre a interrogare gli occupanti scorrendo l'esercito. A ciò si aggiunge lo spostamento della coda con pop_front.

**Proposta:** indice immutabile coordinate→ID costruito con la mappa e condiviso tramite Match; cursore nella coda BFS. Un indice degli occupanti è una seconda fase: richiede copertura di deployment, movimento, sconfitta, revive e caricamento, e deve mantenere più identità sullo stesso esagono.

**Rischio:** basso per indice della mappa, medio/alto per occupanti. Non cambiare ordine deterministico dei percorsi.

### A08 — Scansioni UI a ogni fotogramma — P2

**Evidenza:** `scripts/ui/local_match_controller.gd:466`, `_process()`; `scripts/board/board.gd:294`, `_process()` e `:872`, `_sync_sleeping_markers()`; `scripts/board/hex_cell.gd:391`, `_process()`.

Il controller cerca ricorsivamente le RichTextLabel e verifica i poligoni delle celle selezionabili; il board sincronizza marker e attraversa l'esercito; le celle controllano numeri vita e colori. Parte di questo è necessaria per le animazioni, ma parte riguarda membership e stato che cambiano soltanto dopo eventi.

**Proposta:** mantenere riferimenti alle sole label vita; aggiornare i candidati quando cambia la selezione; sincronizzare la presenza dei marker su eventi e lasciare ai marker animazione e posizionamento. Misurare prima di sostituire la logica geometrica di picking.

**Rischio:** medio/alto: preservare cutout del puntatore, beat Slash, input attraverso la UI e snapshot.

### A09 — Manifest grafico riletto per ogni figura — P2

**Evidenza:** `scripts/board/board_character.gd`, `setup()` intorno alla riga 81.

Ogni figura rilegge e interpreta manifest.json e ricrea gli array dei frame. Le texture caricate possono già essere condivise dal sistema risorse: non è corretto assumere una nuova decodifica di ogni PNG per ogni load.

**Proposta:** condividere manifest interpretato e descrittori/array di animazione per appearance; mantenere per istanza materiale, playback, fade e postura. Gestire esplicitamente invalidazione in sviluppo, se necessaria.

**Rischio:** medio. Il vantaggio reale va misurato soprattutto alla creazione delle figure e dei travelling overlay.

### A10 — Duplicazione esatta della ricerca ritratto — P2

**Evidenza:** `scripts/board/hex_cell.gd:878` e `scripts/ui/local_match_controller.gd:968`, `_card_art_path()`.

I corpi coincidono: stessa mappatura BoardCharacter, estrazione ID, fallback sul nome e controllo esistenza.

**Proposta:** un helper di presentazione condiviso, con lo stesso ordine dei fallback. È una deduplicazione circoscritta e a basso rischio.

### A11 — Geometria Cannon/Gore quasi duplicata — P2

**Evidenza:** `scripts/combat/combat_resolver.gd:645`, `_cannon_hexes()`; `:814`, `_straight_line_hexes()`.

Condividono controllo assiale, distanza, direzione e raccolta delle tessere; il secondo impone anche che il risultato termini sul bersaglio.

**Proposta:** condividere il calcolo della linea e mantenere esplicita la differenza sulla destinazione. Non sostituire alla cieca una funzione con l'altra.

**Rischio:** medio: conservare attraversamento del vuoto della mappa, ordine, portata e regole distinte degli attacchi.

### A12 — Vocabolario delle azioni e introspezione dei selettori distribuiti — P2

**Evidenza:** `scripts/board/hex_cell.gd:434–494`; `scripts/ui/local_match_controller.gd:1201–1261`; `scripts/ui/effect_text.gd`; `scripts/ui/game_icons.gd`.

Compatto del board, menu e descrizione estesa ricostruiscono parti delle stesse informazioni: famiglia dell'azione, range, parametri e fallback delle icone. `_selector_distance()` e `_effect_range()` riconoscono gli stessi tipi di selettore. GameIcons centralizza già una parte del vocabolario.

**Proposta:** completare i metadati di presentazione condivisi e riusare estrazione di range e fallback; mantenere formatter distinti per testo compatto, testo esteso e pulsanti. Non introdurre un parser DSL.

**Rischio:** medio: evitare che il testo mostri bonus doppi o portate diverse da quelle legali.

### A13 — Storici di deduplicazione senza pulizia durante la partita — P2

**Evidenza:** `scripts/runtime/rules_runner.gd:13`, `dispatched_occurrences`; `:29`, `acknowledged_triggers`; inserimenti in capture_event/release_trigger_presentation e clear soltanto in reset.

Le chiavi aumentano con eventi e trigger. WeakRef evita di trattenere le esecuzioni, ma non elimina le voci del dizionario.

**Proposta:** definire prima la durata necessaria della protezione exactly-once; pulire WeakRef esaurite e limitare gli ID soltanto quando nessun percorso legittimo può ripresentarli.

**Rischio:** alto se la pulizia è prematura. Crescita osservabile staticamente; impatto memoria non misurato. Nessuna cancellazione indiscriminata a ogni drain.

### A14 — Compatibilità Troople apparentemente senza consumatori — P3

**Evidenza:** `scripts/model/troople.gd:1–3`; ricerche nel codice, scene, test e strumenti.

La classe è soltanto un alias di TargetRef. Non risultano consumatori eseguibili nel perimetro cercato; esistono riferimenti nel vecchio diagramma.

**Proposta:** eliminazione candidata dopo verifica dei riferimenti UID/risorse e dell'eventuale uso esterno. Beneficio principalmente di chiarezza, non prestazionale.

### A15 — Residui vuoti e scaffold non collegati al flusso principale — P3

**Evidenza:** `scripts/runtime/control.gd`, file solo commento; `scripts/ui/unit.gd`, callback vuoti; `scenes/unit.tscn`; `scripts/ui/system_placeholder.gd`; `scenes/server/server.tscn`; `scripts/ui/game.gd` e `scenes/game.tscn`.

ControlResolver è l'implementazione attiva. La vecchia unità non svolge lavoro. La scena server contiene placeholder espliciti Network/Persistence ed è distinta dal punto di ingresso locale.

**Proposta:** rimuovere il placeholder control e valutare archiviazione/rimozione della vecchia scena unit. Per lo scaffold server decidere se conservarlo come progetto futuro documentato; non classificarlo automaticamente come errore o autorizzazione a implementare l'online.

**Rischio:** basso dopo controllo delle dipendenze. Non cancellare singoli script lasciando scene con riferimenti rotti.

### A16 — Campi di testo legacy senza lettori attivi trovati — P3

**Evidenza:** `scripts/model/unit_info.gd:7–8`, hex_text/hover_text; commenti in EffectText e LocalMatchController che dichiarano di non consultarli.

La ricerca trasversale non individua letture/scritture applicative oltre alle dichiarazioni. Oggi il testo deriva dagli oggetti degli effetti.

**Proposta:** rimuovere i due campi dopo controllo di eventuali risorse/esportazioni esterne. Conservare testi e documentazione delle regole.

### A17 — Dati Bow serializzati due volte per compatibilità — P3

**Evidenza:** `scripts/model/unit_info.gd:36–40`; `scripts/runtime/match_snapshot.gd:60–61`, `:190–193`.

Il salvataggio scrive sia props sia bow_damage_bonus/bow_range_bonus derivati dagli stessi contatori. Il ripristino mantiene un fallback per formati precedenti.

**Proposta:** lasciare la lettura legacy in una migrazione esplicita; scrivere una sola rappresentazione nel prossimo formato, se si decide una nuova versione. Non rimuovere ora il fallback perdendo salvataggi esistenti.

**Rischio:** medio. Riduzione di ridondanza, vantaggio prestazionale marginale.

### A18 — API alternative e wrapper ancora utilizzati — P2 documentale / P3 migrazione

**Evidenza:** `scripts/effects/phrase_selection.gd`; `tests/fire_test.gd` e `tests/selection_test.gd`; `scripts/board/board.gd:691`, select_phrase/select_effect; `scripts/model/unit_info.gd:374`, eval.

PhraseSelection è usato ripetutamente dai test; i percorsi diretti board sono anch'essi verificati dai test. UnitInfo.eval non mostra chiamanti applicativi nel perimetro cercato, ma espone un ingresso senza la contabilità automatica del comando managed.

**Proposta:** classificare esplicitamente API managed, primitive e adattatori di test; correggere le mappe dei chiamanti. Eventuale migrazione dei test prima di eliminare wrapper. Non considerare tutte queste funzioni codice morto.

**Rischio:** alto se si unificano i percorsi ignorando costi e token; basso per la documentazione.

### A19 — Documentazione storica e contratti non allineati — P2

**Evidenza:** `docs/effect-creation-and-resolution.drawio`, riferimenti a Match.army[player][unit_index], Troople e vecchi candidates(); `docs/PROJECT_SIZE.md:3`, snapshot esplicitamente datato 19 ottobre; `scripts/model/unit_info.gd:372–375`; contratti che attribuiscono chiamate a vecchi percorsi UI.

Il diagramma presenta come implementato un modello superato. PROJECT_SIZE è uno snapshot storico valido, ma non fotografa più la dimensione corrente: riportava 50 script/7.350 righe contro 74/12.943. Il commento di UnitInfo.eval attribuisce al controller un percorso board mentre il flusso managed attuale entra nel runner. Il conteggio automatico segnala inoltre 75 funzioni da controllare per contratti adiacenti mancanti.

**Proposta:** aggiornare o marcare il diagramma come storico; aggiungere un inventario corrente senza cancellare la storia utile; revisionare i contratti realmente obsoleti e completare quelli mancanti. Conservare caller map ed esempi.

## Cosa preservare

- Definizioni riutilizzabili e stato di attivazione in EffectExecution/PhraseExecution.
- TargetRef con identità stabile, proprietà esplicite e conversione centralizzata in TargetResolver.
- Revalidazione prima del commit e controlli di legalità: ripetere una validazione alla frontiera di mutazione non è automaticamente una ridondanza eliminabile.
- Separazione Action → CombatResolver: i wrapper piccoli possono esprimere un confine utile.
- StateModifier e ContinuousEffect hanno sovrapposizioni concettuali, ma non costituiscono da soli una prova che una delle due API vada eliminata.
- Record Bow/Fire/Gore/Cannon distinti: campi simili non autorizzano una gerarchia comune se cattura, risoluzione ed eventi differiscono.
- Counter permanenti e temporanei distinti; grant continui e temporizzati; effetti copiati e upgrade legati a destinatario/esecuzione.
- Regole intenzionalmente diverse dal JS, gate dei trigger a due identità e ordine attacco → Slash → Skull.
- Test comportamentali esistenti. Fixture ripetute possono favorire la leggibilità; estrarle soltanto se condividono davvero invarianti stabili.
- `.godot`, `.uid`, `.import`, runtime locale e originali PixelLab: non sono codice morto soltanto perché generati o non citati letteralmente. Nessuna cancellazione proposta senza un audit specifico delle risorse.

## Piano proposto per approvazione

| Lotto | Contenuto | Condizione di completamento |
| --- | --- | --- |
| 1 — Pulizia verificabile | A10, A14–A16, A19; classificazione A18 | Riferimenti/scene integri, contratti e mappe aggiornati; nessuna variazione delle regole |
| 2 — Affidabilità | A01, A02 | Unica regola di preflight, caricamento validato prima della mutazione, regressioni mirate aggiunte |
| 3 — Calcoli e geometria | A03, A07, A11; riuso locale A06 | Risultati e ordine deterministico invariati, conteggio di scansioni ridotto |
| 4 — Presentazione | A04, A05, A08, A09, A12 | Continuità animazioni/input preservata; confronto misurato in scenari rappresentativi |
| 5 — Compatibilità e memoria | A13, A17, eventuale migrazione A18 | Politica exactly-once e migrazione salvataggi documentate e verificate |

Consiglio di approvare prima i lotti 1 e 2. Il lotto 1 può escludere lo scaffold server se si vuole conservarlo. Nessun lotto autorizza milestone ulteriori della roadmap.

## Verifiche da prevedere dopo approvazione

Nessuna è stata eseguita in questo audit. L'esecuzione rimane subordinata a un prompt che termini con `TEST`, come richiesto da AGENTS.md. L'aggiunta/aggiornamento dei test comportamentali necessari resta parte dell'implementazione anche quando non è autorizzato eseguirli.

- Costi/runner: selection_test, m2_test e trigger_state_test, con casi cumulativi e pagamento atomico.
- Snapshot: local_match_test e regressioni per dati invalidi, formati v1/v2, copie/upgrade e attacchi pendenti.
- Geometria/controllo: selection_test e fire_test; pareggi, regione condivisa, percorsi bloccati e ID deterministici.
- Presentazione: presentation_test e verifica visiva di Bash, hover, movimento, trigger, Slash/Skull e caricamento; un test headless da solo non prova la fluidità.
- Effetti interessati: rat_effects_test e woodland_effects_test secondo la modifica, con risultato, eleggibilità/proprietà e casi che non devono attivarsi.
- Prestazioni: misurare tempi di refresh/ricerca percorso, chiamate al controllo, scansioni per frame, creazioni di nodi e crescita degli storici; confrontare stesso scenario e stessa configurazione. Non promettere guadagni percentuali prima delle misure.

## Decisione richiesta

Approvare uno o più lotti o singoli identificativi A01–A19. Fino all'approvazione non verrà modificato il codice. Il report propone interventi incrementali, senza riscrittura generale, parser DSL o cambio delle regole del gioco.

## Stato di attuazione — pulizia conservativa autorizzata, 26 ottobre 2026

Applicati A10, A14 e A16; A15 limitato al placeholder control e alla vecchia
scena unit con script/UID. A12 applicato soltanto alla lettura delle portate e
al vocabolario glyph comune. A19 applicato alle mappe dei file/chiamanti coinvolti,
alla classificazione storica del diagramma e al contratto UnitInfo.eval.
La ricerca ritratti ora vive in BoardCharacter, la lettura della portata mostrata
in EffectText, i glyph di fallback comuni in GameIcons. Rimossa anche una doppia
ricerca del ritratto nello stesso rendering Bash.

Conservati PhraseSelection, API dirette e compatibilità salvataggi; nessun cambio
al sistema di costi, combattimento, cache, timing o regole delle carte. Non sono
stati eseguiti test né avviato Godot. Le verifiche di questa tranche sono statiche:
ricerca di chiamanti residui, riferimenti alle risorse rimosse e revisione dei
corpi estratti. L'inventario precedente descrive il codice prima della pulizia.
