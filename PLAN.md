# Prompt

Client Flutter rapide, prive et adapte au mobile pour un serveur OpenCode personnel. Prompt cible Android, Linux et le Web, avec une connexion reservee au VPN WireGuard de l'utilisateur. La premiere livraison privilegie Android, sans creer de code, de modele de donnees ou de navigation qui empecherait Linux et le Web d'atteindre la parite.

## Principes produits

- Ne jamais interrompre une generation lorsqu'un nouveau message est envoye : le comportement par defaut est une file d'envoi par session.
- Donner a l'utilisateur un controle explicite sur les permissions, les transferts, le stockage local et la dictee.
- Privilegier la reactivite a tout effet visuel. L'application doit rester utilisable pendant un streaming, un diff ou une sortie d'outil volumineuse.
- Ne pas ajouter de dependance generique si Flutter, Dart ou une petite abstraction locale suffit.
- OpenCode reste la source de verite. Le stockage local accelere l'ouverture, permet la reprise et conserve les preferences.
- Aucun analytics, tracking, publicite ou telemetry distante par defaut.

## Cibles et reseau

| Cible | Usage | Contraintes |
| --- | --- | --- |
| Android | Usage mobile principal | Batterie, reseau mobile, permissions micro, clavier logiciel |
| Linux | Poste de travail | Raccourcis clavier, panneaux redimensionnables, keyring systeme |
| Web | Acces leger depuis un navigateur | HTTPS obligatoire pour micro et stockage securise, cache moins fiable |

Le serveur OpenCode, le serveur de transcription eventuel et le reverse proxy sont ecoutes uniquement sur l'adresse de l'interface WireGuard. Le pare-feu n'autorise que le sous-reseau WireGuard.

Android et Linux acceptent toute origine HTTP dont l'adresse est RFC1918, dans la plage CGNAT Tailscale `100.64.0.0/10`, ou IPv6 ULA, afin que chaque utilisateur WireGuard ou Tailscale puisse saisir son propre serveur sans adresse codee en dur. Cette validation est appliquee par le client avant chaque requete. Le client Web doit utiliser une origine HTTPS, meme si elle est elle aussi joignable seulement par WireGuard.

Le client Web est servi en HTTPS par le reverse proxy, idealement sous la meme origine que l'API OpenCode :

```text
https://opencode.vpn.example/         API OpenCode proxifiee
https://opencode.vpn.example/client/  Flutter Web
```

Cette disposition evite CORS et est necessaire au microphone du navigateur. WireGuard chiffre le transport prive, mais ne remplace pas HTTPS dans les exigences du navigateur.

## Contrat OpenCode

Prompt utilise l'API REST OpenCode pour les projets, sessions, messages, agents, modeles, providers, fichiers, commandes, taches, diffs, VCS, MCP, LSP, configuration, permissions et questions. Les reponses et changements d'etat arrivent par Server-Sent Events (SSE).

Implementation reseau :

- Un seul abonnement SSE par connexion serveur, demultiplexe par projet et session.
- Envoi non bloquant avec `POST /session/{id}/prompt_async`.
- Annulation explicite avec `POST /session/{id}/abort`.
- Reconnexion exponentielle avec jitter et plafond; apres reconnexion, relecture REST de la session active plutot que confiance aveugle dans un flux manque.
- Adaptateur versionne entre l'interface de l'application et l'API OpenCode. Les capacites sont activees selon la version et le schema exposes par le serveur; les endpoints experimentaux ne sont jamais supposes disponibles.

## Reference OpenCode et objectif Prompt

OpenCode fournit une meme application React/Solid pour son Web et son Desktop Electron. Il n'existe pas de client Android natif officiel. Prompt doit couvrir chaque capacite utilisateur de ces surfaces, lorsqu'elle est exposee par le serveur, puis l'adapter a un ecran tactile et a un usage distant.

Les endpoints v1 documentes sont la base de compatibilite. Les endpoints v2 et `experimental` sont isoles derriere des facades de capacite : ils sont proposes uniquement si le serveur les annonce et l'utilisateur les active. Aucun ecran ne doit casser si une capacite experimentale disparait ou evolue.

| Domaine OpenCode | Capacites Web/Desktop a couvrir | Prompt Android, meilleur comportement | Implementation et parite |
| --- | --- | --- | --- |
| Serveurs et demarrage | Liste de serveurs, verification de sante, choix du serveur, projets recents, onboarding | Assistant de connexion court : URL WireGuard, test, authentification, diagnostic reseau et import d'une URL de connexion. Les parametres serveur proposent un rechargement OpenCode apres confirmation : les generations actives s'arretent, les instances de projet sont recreees et la configuration, les skills et MCP sont relus; les sessions restent disponibles et le processus HTTP OpenCode n'est pas redemarre. | Profils locaux, `GET /global/health`, `POST /global/dispose`, secrets en stockage securise. Apres succes, diagnostics, sessions et capacites sont rafraichis pour le profil actif. Linux/Web reprennent les memes profils; Web exige HTTPS. |
| Projets et emplacements | Ouvrir/changer/fermer projet, projets recents, arborescence, branche et statut Git, selecteur de repertoire | Liste de projets avec recherche et dernier acces. Le choix de repertoire est une recherche serveur, pas un faux explorateur du telephone. Une session ouverte ferme automatiquement le tiroir de projets. | REST projet, fichier, VCS et recherche. Android ne tente jamais d'ouvrir un chemin du VPS dans son propre systeme de fichiers. |
| Sessions | Creer, lister, rechercher, renommer, supprimer, archiver, restaurer, enfants/sous-agents, fork, parent, sessions recentes | Accueil de sessions rapide, filtres par projet/etat, recherche locale instantanee et chargement pagine. Une session enfant montre son parent et son objectif. L'archive est accessible, pas cachee dans un menu contextuel. | Cache Drift borne, pagination curseur v2 quand disponible, fallback v1 limite. Les panneaux Linux/Web apportent navigation persistante et raccourcis. |
| Conversation | Messages, texte, raisonnement, changement agent/modele, outils, couts/tokens, compaction, resume, abort, fork | Transcript lisible et virtualise; les details sont developpables sans bloquer le texte. Le flux reste utilisable quand l'application revient au premier plan ou change de reseau. | Reducer SSE par parties de message, relecture REST apres reprise, historique pagine et marqueurs de synchronisation. |
| Composeur | Texte, commandes `/`, commandes shell, `@fichier`, alias de references, pieces jointes, collage image, historique de saisie, selection agent/modele/effort | Champ multi-ligne fixe, touche explicite Nouvelle ligne, collage de texte entier editable et collage d'image depuis le presse-papiers. Aucun texte colle n'est masque dans un placeholder. Les controles agent/modele/effort restent accessibles dans une feuille dediee, jamais superposes au clavier. | Parts de prompt OpenCode, service presse-papiers/fichiers conditionnel. Controle de taille avant transfert: au plus 5 fichiers, 10 MiB par fichier et 25 MiB au total. Les pieces jointes partent en parts `file` avec une URL `data:` et sont persistees avec leur prompt dans la base chiffree, afin qu'un prompt avec piece jointe survive au redemarrage comme un prompt texte. |
| File et interruption | Prompt pendant generation, interruption, livraison differree ou immediate | `Ajouter a la file` est le bouton normal. La file est visible, editable, supprimable, reordonnable et persistante. `Envoyer maintenant` explique l'annulation et attend un etat terminal avant envoi. | Machine a etats locale en Drift, reconciliation apres crash/reconnexion, aucune reemission aveugle si l'acceptation serveur est inconnue. |
| Agents, modeles et providers | Agents Build/Plan/sous-agents, agents configures, skills, catalogue provider/modele, variantes de raisonnement, favoris/recents, providers OpenAI compatibles, connexion OAuth/API key | Selecteur recherche avec favoris, recents, disponibilite et effort. Les options mortes ou incompatibles sont masquees apres erreur verifiee. Connexion provider par navigateur externe puis polling d'integration, jamais callback local suppose. | API agent/provider/config/auth et facade Integration v2. Preferences de modele locales; les cles provider restent cote OpenCode sauf saisie explicite dans le flux serveur. |
| Outils et controle agent | Bash, lire/ecrire/editer, recherche, glob, LSP, formatters, webfetch/search, apply patch, custom tools, todos, skills, commandes et MCP | Chronologie compacte avec statut, duree et sortie bornee. Une sortie lourde se charge a la demande. Les todos sont accessibles dans un panneau et relient chaque tache a la conversation. | Part renderer par type, API outils/commandes/todo/skill/MCP. Aucun rendu ANSI, JSON ou Markdown lourd dans l'isolate UI. |
| Permissions et questions | Regles allow/ask/deny, une fois/toujours/refus, permissions memorisees, outils et commandes shell, questions multi-choix/texte | Dock non dismissible au-dessus du composeur, avec resume clair du risque. Une modification multi-fichiers se revise fichier par fichier, avec diff et actions clavier/TalkBack. Les demandes survivent au redemarrage et sont remontees avant toute reprise de file. | API permission/question v1 puis v2 si disponible; cache local de presentation seulement. Ecran Parametres pour consulter/supprimer les permissions memorisees serveur. |
| Fichiers, diff et VCS | Arborescence, lecture, recherche texte/symbole, statut, diff de session, diff Git, undo/redo snapshot, commentaires de ligne, ouvrir dans IDE | Vue fichier lecture seule optimisee mobile, recherche, fichiers modifies et diff par fichier. Les gros diffs sont pagines/virtuelises. Les commentaires de ligne sont locaux tant que le serveur ne les persiste pas, clairement etiquetes comme tels. | API file/find/symbol/status/session diff/VCS/revert. Android copie chemin/contenu ou partage un export; Linux peut ouvrir IDE/fichier via une interface plateforme. |
| Terminal distant | Onglets terminal, creation/fermeture, redimensionnement, sortie ANSI, entree clavier, statut/exit code | Terminal plein ecran avec barre de touches programmees (`Ctrl`, `Alt`, fleches, Tab, Esc), selection/copie et avertissement clair qu'il agit sur le VPS. | PTY experimental : creation REST, ticket usage unique, WebSocket binaire, renderer ANSI dans une facade `RemoteTerminal`. Disponible Android, Linux et Web si le serveur l'autorise. |
| Workspaces et synchronisation | Worktrees, creer/supprimer workspace, statut, deplacer une session, copier projet, sync/replay/steal d'historique | Ecran experimental masque par defaut : choisir un workspace, voir son statut, deplacer explicitement une session avec avertissement. Pas de synchronisation silencieuse ou de conflit masque. | Facades v2 workspace/sync/control-plane; pagination et OAuth Integration v2 sont utilises des maintenant, UI workspace complete seulement derriere capability flag. |
| Configuration | Lire/patcher `opencode.json`, agents, permissions, MCP, formatters, LSP, plugins, references, policies, compaction, share | Parametres simples pour les options frequentes et editeur JSON avance avec validation/schema, diff avant application et sauvegarde explicite. La configuration serveur est toujours distinguee des preferences du client. | `GET/PATCH /config`, endpoints config/provider/MCP. Les fichiers config restent sur le VPS; Prompt n'en conserve pas une copie editable sans demande explicite. |
| Themes et raccourcis | Themes app/TUI, mode clair/sombre/systeme, palette de commandes, raccourcis, menus, changelog | Material 3 avec tokens semantiques et presets inspires des themes OpenCode. Android propose palette d'actions, actions rapides et menus accessibles; Linux/Web ajoutent raccourcis configurables et barre de menu. | ThemeData/token map local; commandes comme donnees communes aux boutons, palette et raccourcis. |
| Partage, export et import | Partage public de session, annulation du partage, copier lien, export Markdown/JSON, import CLI, logs/export debug | Partage desactive par defaut et avertissement explicite : le partage OpenCode peut transmettre l'historique a l'infrastructure `opncd.ai`. Export local Markdown/JSON assaini par defaut, apercu avant partage Android. | API share/unshare seulement apres consentement. Export construit depuis le cache/historique pagine; les logs exportes sont toujours rediges. |
| Desktop, OS et cycle de vie | Fenetres multiples, deep links, notifications, presse-papiers, open in app, picker/sauvegarde, mises a jour, zoom, journaux | Android privilegie une seule tache, intents/app links, partage systeme, picker SAF, notifications de fin/permission et reprise fiable. Pas de processus OpenCode local ni de sidecar. | Interfaces plateforme conditionnelles. Linux/Web implementent fenetres/panneaux, raccourcis, export et ouverture dans application lorsque la plateforme le permet. |

### Fonctions supplementaires qui corrigent l'etat de l'art

Les points suivants sont des exigences produit, pas des optimisations optionnelles. Ils viennent d'incidents et de demandes recurrents dans les issues OpenCode.

| Problemes observes | Reponse Prompt et critere d'acceptation |
| --- | --- |
| Un PWA Android perd son SSE apres veille, changement d'application ou retour de reseau et montre un transcript fige ([#17769](https://github.com/anomalyco/opencode/issues/17769), [#33783](https://github.com/anomalyco/opencode/issues/33783)) | A la reprise, afficher `Reconnexion` puis synchroniser par REST avant de declarer le transcript a jour. Un flux silencieux expire avec une erreur visible et une action Reprendre; jamais de spinner infini. Tester verrouillage Android et changement Wi-Fi/mobile. |
| Les messages en file ne peuvent pas etre edites/supprimes, ou sont perdus apres interruption ([#4821](https://github.com/anomalyco/opencode/issues/4821), [#5333](https://github.com/anomalyco/opencode/issues/5333), [#6942](https://github.com/anomalyco/opencode/issues/6942)) | File locale durable avec edition, suppression, ordre, pause et journal d'envoi. Aucun element ne disparait sans action utilisateur ou diagnostic durable. |
| Historique trop lourd sur reseau cellulaire, jusqu'a 30-90 secondes de chargement ([#35895](https://github.com/anomalyco/opencode/issues/35895)) | Chargement par curseur et fenetre visible; pas de prechargement de 200 messages ou de sorties volumineuses. Afficher volume et progression pour une recuperation manuelle. |
| Diff et highlighting bloquent l'interface ([#31195](https://github.com/anomalyco/opencode/issues/31195), [#22650](https://github.com/anomalyco/opencode/issues/22650)) | Diff et Markdown hors isolate UI, rendu progressif, code monospace immediat puis enrichissement differe. Mesurer sur appareil Android modeste. |
| Tiroir sessions mobile inaccessible ou ne se ferme pas ([#37746](https://github.com/anomalyco/opencode/issues/37746), [#28736](https://github.com/anomalyco/opencode/issues/28736)) | Un seul controle de navigation, taille tactile correcte; selection d'une session ferme le tiroir et positionne le focus sur le titre de conversation. Test widget a chaque breakpoint. |
| Collage texte/image incomplet, controle de prompt masque, saisie mobile sans nouvelle ligne ([#8501](https://github.com/anomalyco/opencode/issues/8501), [#906](https://github.com/anomalyco/opencode/issues/906), [#20965](https://github.com/anomalyco/opencode/issues/20965)) | Texte colle totalement editable, image presse-papiers transformee en piece jointe avec apercu, bouton Nouvelle ligne et actions agent/modele toujours disponibles dans une feuille qui respecte le clavier. |
| Permission multi-fichiers illisible ou perdue apres rafraichissement ([#21914](https://github.com/anomalyco/opencode/issues/21914), [#20998](https://github.com/anomalyco/opencode/issues/20998)) | Revue par fichier, index de progression, actions semantiques annoncees, et recuperation des permissions en attente apres reprise avant toute file. |
| Streaming et menus peu accessibles aux lecteurs d'ecran ([#33137](https://github.com/anomalyco/opencode/issues/33137), [#36165](https://github.com/anomalyco/opencode/issues/36165)) | Le texte de reponse en flux reste dans l'arbre semantique avec annonces regroupees. Menus agent/modele/commande exposent libelle, selection et focus TalkBack. |
| Remote/LAN/Tailscale diverge selon l'origine ou le proxy ([#28340](https://github.com/anomalyco/opencode/issues/28340), [#25826](https://github.com/anomalyco/opencode/issues/25826)) | Un seul profil d'origine WireGuard canonique, test de compatibilite a la connexion, et tests d'integration contre le reverse proxy HTTPS reel. Aucune supposition `localhost`. |
| Pas de signal lorsqu'un agent termine ou attend un humain ([#213](https://github.com/anomalyco/opencode/issues/213)) | Notification locale Android configurable pour fin, echec et permission/question. Elle ne conserve ni prompt ni sortie sensible dans son contenu. |

## Fonctionnalites de Prompt

### Connexion et securite

- Profils de serveurs prepares des le depart, avec un profil WireGuard courant.
- URL, identifiant et mot de passe OpenCode; test de sante et erreur lisible en cas de VPN absent, serveur indisponible ou authentification refusee.
- Authentification HTTP Basic OpenCode avec `OPENCODE_SERVER_PASSWORD` active cote serveur.
- Identifiants conserves dans le stockage securise de la plateforme, jamais dans Drift ni les journaux.
- Indicateur permanent mais discret du serveur, de l'etat WireGuard et de l'activite de synchronisation.
- Effacement complet des donnees locales et deconnexion.

### Projets et sessions

- Liste, recherche et ouverture des projets OpenCode.
- Liste, creation, renommage, suppression, recherche et reprise des sessions.
- Indicateurs de session : active, generation, permission en attente, erreur, messages en file.
- Derniere session ouverte restauree au lancement.
- Toutes les capacites de session exposees par le serveur sont presentees lorsque celui-ci les supporte : branches/forks, partage, resume, revert et operations VCS.

### Conversation et agent

- Historique pagine et virtualise; Markdown, tableaux simples, liens et blocs de code selectionnables.
- Code monospace, copie immediate, retour a la ligne configurable et rendu enrichi differe si le message est encore en flux.
- Selecteurs compacts d'agent, provider et modele, commandes `/`, mentions et recherche de fichiers.
- Etats de raisonnement, erreurs, couts, etapes et sorties d'outils lisibles sans encombrer le transcript.
- Cartes repliables pour outils, taches, fichiers produits et sorties longues.
- Bouton Annuler toujours accessible durant une execution.
- Permissions et questions ancrees au-dessus du composeur avec decisions `une fois`, `toujours` et `refuser` selon les choix exposes par OpenCode.

### File d'envoi

La file d'envoi est une fonctionnalite centrale et locale a Prompt.

- Pendant une generation, `Envoyer` ajoute le prompt a la file persistante de cette session; il n'interrompt jamais l'agent par defaut.
- La generation suivante part automatiquement seulement lorsque la precedente est terminee et qu'aucune permission ou question ne bloque la session.
- Chaque element est modifiable, supprimable, reordonnable ou envoyable immediatement.
- `Envoyer maintenant` avertit que le flux actif sera interrompu, appelle l'annulation, attend l'etat terminal du serveur puis envoie le nouveau prompt. Il n'existe aucune interruption implicite.
- La file est reprise apres redemarrage ou coupure reseau uniquement apres reconciliation avec le serveur.
- Une erreur non recuperable, une permission ou une suppression de session met la file en pause avec une raison explicite.

### Fichiers, outils et revue de code

- Pieces jointes via le selecteur de fichiers natif et fichiers du workspace via recherche/mention.
- Previsualisation texte, fichiers produits, copie et export lorsque la plateforme le permet.
- Liste des fichiers modifies par session et diff unifie lisible sur mobile comme sur bureau.
- Navigation entre fichiers modifies, commandes de formatage, LSP, MCP et VCS exposes par OpenCode.
- Les actions sensibles restent soumises aux permissions du serveur et sont toujours visibles dans la conversation.

#### PoC de Contingent Review (Slices 1 et 2)

Pour OpenCode 1.18.25, le PoC resout le diff non vide le plus recent produit par un message utilisateur de la session courante avant de figer le snapshot borne et immuable en memoire (au plus 20 fichiers et 200 000 caracteres de patch). Il propose par defaut deux passes independantes, correctness et security, et permet a l'utilisateur d'ajouter la passe tests/regressions. Chaque passe active utilise un modele distinct dans une session enfant OpenCode portant `parentID`; la selection par defaut maximise la diversite des providers connectes declares par la configuration OpenCode de l'utilisateur avant de reutiliser un provider. La creation est deny-all et chaque requete est tool-free; le diff est transmis comme donnees non fiables dans une demande a sortie JSON Schema structuree.

Le PoC reste strictement en lecture seule: aucun Drift, fichier, workspace, Git, auto-fix, commit ou merge. Chaque passe a un timeout par defaut de 120 secondes et l'execution concurrente des passes une limite globale de 240 secondes apres preparation du snapshot et des sessions enfants. Un repository serialise ses runs. Un timeout declenche immediatement l'abort officiel de l'enfant; le nettoyage est confirme ou signale comme incertain dans un echec type, sans relancer automatiquement le provider. L'etat du run represente les succes partiels, echecs provider, timeout, annulation, metriques, provenance, hypotheses et desaccords sans detruire les opinions originales. La reconciliation utilise un polling REST borne des messages et du statut, et ne declare jamais un resultat sans message assistant termine. Le controle Android est prevu par une facade et un ViewModel adaptatifs; le debat ou l'adjudication au-dela du regroupement des desaccords est reporte.

### Dictee vocale locale

- Les **Voice settings** sont globaux a l'application, jamais lies a une
  session. Apres la selection explicite d'un modele local, le bouton **Voice
  input** apparait a cote de l'envoi dans chaque composeur et injecte les
  transcriptions partielles puis finale dans le brouillon editable. Aucun
  appel STT distant ni demande de permission au lancement n'est effectue.

- Capture explicite : appui-maintien sur Android, demarrer/arreter sur Linux et Web.
- Prompt uses `sherpa_onnx` 1.13.5 (Apache-2.0) with two distinct streaming
  Zipformer INT8 models, explicitly selected for French or English. Automatic
  language mode is not currently supported. Partial and final text remains
  editable before sending; the draft and prior segments stay local.
- Arret immediat du microphone lorsque l'application devient inactive; aucun enregistrement permanent.
- One explicit Install action downloads the four runtime files from pinned
  Hugging Face revisions, verifies size and SHA-256, stores them atomically in
  private application support storage, and selects the language model. Prompt
  does not bundle model files and exposes a Remove action per language.
- Un seul recognizer est charge dans un isolate dedie pendant le mode vocal.
  Chaque segment demarre un nouveau stream. A l'arret du mode vocal, Sherpa
  redecode en une passe globale tous les segments conserves en memoire, avec
  une courte separation silencieuse, puis remplace le brouillon concatene. Il
  conserve au maximum deux minutes d'audio; au-dela, les transcriptions par
  segment restent le repli sans croissance memoire. Il n'y a pas de passe
  finale Whisper. L'audio est aussitot ecrase et reste libere
  sur tous les chemins de fin, d'annulation et de cycle de vie.
- Les hypotheses partielles, les segments finalises et la correction globale
  sont normalises en minuscules avant leur insertion dans le brouillon.
- Android et Linux utilisent le moteur natif Sherpa; Web reste une
  implementation typed unavailable et ne demarre aucun moteur vocal.
- Option VPS WireGuard possible uniquement par consentement explicite, comme repli si aucun modele local n'est installe. Audio et transcription ne sont jamais envoyes a un tiers.

## UX et navigation

### Direction visuelle

Un cockpit de developpement personnel : dense sans etre surcharge, sombre par defaut, typographie lisible et code monospace. Les couleurs sont reservees aux etats importants : generation, permission, succes, erreur et changements Git. Les animations sont courtes, informatives et respectent la preference systeme de mouvement reduit.

### Android

- Accueil projets/sessions, puis conversation plein ecran.
- Panneaux contextuels en feuilles modales : outils, taches, fichiers, diff, file d'envoi et selection de modele.
- Composeur fixe adapte au clavier logiciel.
- Pastille `n messages en attente` au-dessus du composeur ouvrant la file.

### Linux et Web larges

- Trois panneaux redimensionnables : navigation a gauche, conversation au centre, contexte a droite.
- Panneau droit a onglets : Taches, Fichiers, Diff, Outils et Contexte.
- Palette de commandes et raccourcis : nouvelle session, recherche, envoyer, annuler, changer agent/modele.

### Web et ecrans etroits

- Les panneaux deviennent des tiroirs et feuilles modales au lieu de reproduire une interface bureau reduite.
- Les zones tactiles, le focus, la selection de texte et le lecteur d'ecran sont testes sur toutes les largeurs.

## Performance

L'objectif est une interface a 60 fps stable en generation et une saisie qui ne bloque jamais.

- `CustomScrollView` et slivers pour conversations, sessions, listes d'outils et diffs.
- Identifiants stables par message et partie de message. Seul le bloc modifie par le delta SSE est reconstruit.
- Deltas SSE regroupes avant rendu; pas de reconstruction pour chaque token.
- Analyse Markdown, JSON volumineux, diffs et traitement de fichiers deplaces hors de l'isolate UI lorsque le volume le justifie.
- Sorties d'outils, diffs et fichiers charges a la demande; aucune prelecture de donnees lourdes.
- Cache d'images et de fichiers borne par taille et age.
- Tests de performance sur longues sessions, streaming continu, gros diffs, appareil Android modeste et navigateur Web.

## Confidentialite, batterie et donnees

### Confidentialite

- Aucune telemetrie distante par defaut; export de diagnostic uniquement sur action explicite et apres redaction.
- Aucun log de prompt, message, token, mot de passe, entete HTTP, audio ou contenu de fichier.
- Les notifications locales sont desactivees jusqu'a une action explicite dans
  les parametres. Leur permission n'est jamais demandee au lancement ni en
  reaction a un evenement serveur. Leur contenu reste generique (fin ou echec
  de session) et ne contient ni prompt, message, sortie d'outil, fichier,
  chemin ou identifiant secret.
- Web requiert HTTPS et un geste utilisateur direct pour la permission de
  notification; les navigateurs ne planifient pas ces notifications. Sous
  Linux, la livraison depend du serveur de notifications de bureau et ne
  comporte pas de permission d'execution.
- Audio en memoire uniquement. Il est detruit apres transcription, reussie ou echouee.
- Pieces jointes locales : maximum 10 MiB chacune, 5 fichiers et 25 MiB au
  total. La selection du composeur reste en memoire et est ecrasee et liberee
  a la suppression, tentative d'envoi, inactivite, sortie de conversation et
  destruction. Une copie est conservee dans la file chiffree seulement tant
  que le prompt n'est pas envoye ou que son acceptation est inconnue, afin de
  permettre une reprise explicite apres redemarrage. Elle est effacee des que
  le serveur accuse reception du prompt.
- Android/Linux : cache Drift chiffre avec SQLite3MultipleCiphers; cle aleatoire dans le stockage securise systeme.
- Web : pas de chiffrement SQLite/WASM equivalent. Aucun cache durable du contenu de conversation par defaut, uniquement les metadonnees. L'utilisateur peut activer ce cache en connaissance de cause.
- Registre local minimal et borne pour les diagnostics, avec rotation courte.

### Batterie et donnees

- Aucun flux SSE, micro, polling ou reconnexion en arriere-plan.
- SSE ferme lorsque l'application est inactive, le VPN est indisponible ou aucune session n'est active.
- Synchronisation au retour au premier plan et a la demande, avec reprise progressive.
- Modes utilisateur : Wi-Fi uniquement pour transferts lourds, donnees reduites, economie d'energie, telechargement automatique de fichiers et conservation locale.
- En mode donnees reduites : pas de prechargement, sorties d'outils tronquees puis chargees a la demande, pas de cache de pieces jointes et telechargement vocal seulement en Wi-Fi.

## Architecture et dependances

Structure initiale :

```text
lib/
  main.dart
  app/
  core/
  features/
    connection/
    projects/
    sessions/
    chat/
    queue/
    review/
    providers/
    terminal/
    workspace/
    voice/
    settings/
    export/
  data/
    opencode_api_service.dart
    opencode_event_service.dart
    local_database.dart
    secure_credentials_service.dart
```

Les vues ne contiennent pas de logique metier. Les ViewModels portent l'etat et les commandes. Les repositories reconcillient API, SSE et cache Drift. Les services encapsulent le transport, la securite et les integrations plateforme.

Dependances de production a justifier :

```yaml
drift:
drift_flutter:
http:
flutter_secure_storage:
file_selector:
markdown:
record:
connectivity_plus:
sherpa_onnx: ^1.13.5 # Apache-2.0, Android et Linux
```

Les notifications locales et le renderer ANSI du terminal ne seront ajoutes comme dependances que si une evaluation confirme leur maintenance, licence et compatibilite cible. Ils ont une exigence produit concrete; ils ne justifient pas un package generique de plus sans cette verification.

Dependances de developpement :

```yaml
drift_dev:
build_runner:
flutter_lints:
```

Pas de package de state management, routing, SSE, icones, syntax highlighting, cache HTTP ou design system par defaut. Flutter fournit les primitives necessaires.

Flutter Rust Bridge et Dart Native Assets ne sont pas requis par l'integration Sherpa actuelle. Web reste typed unavailable; aucune strategie WASM ou Whisper n'est retenue.

## Donnees Drift

- `server_profiles` : adresse et preferences non secretes.
- `projects` et `sessions` : cache et metadonnees de navigation.
- `messages` et `message_parts` : cache de transcript et etat de streaming.
- `queued_prompts` : ordre, contenu, etat, causes de pause et identifiants de session.
- `ui_preferences` : theme, panneaux, dernier contexte, modes donnees/batterie.
- `local_models` : modele vocal, taille, checksum, langue et date d'acces.

Les secrets, cles et mots de passe ne figurent dans aucune table Drift.

## Qualite et verification

- Tests unitaires des ViewModels, de la file d'envoi, de la reconciliation SSE et des permissions.
- Tests de contrat contre des fixtures d'evenements OpenCode et version de serveur connue.
- Tests d'integration Drift, y compris migration et suppression complete des donnees.
- Tests widget pour streaming, reprise, file, dictee, accessibilite et layouts mobile/bureau.
- Tests de performance et profilage Flutter DevTools en mode release.
- CI Android, Linux et Web; la verification de la voix native Sherpa est separee des controles Web typed unavailable.

## Ordre de livraison Android-first

Toutes les capacites de l'inventaire font partie du produit. L'ordre livre d'abord les parcours Android qui corrigent les defauts constates du Web, tout en etablissant les interfaces et modeles partages necessaires a Linux et Web.

1. Socle Flutter Android, themes/tokens, navigation adaptative, profil WireGuard, HTTPS, authentification, REST/SSE, stockage securise, health check et journal redige.
2. Projets, sessions paginees, transcript streaming, composeur complet, collage, pieces jointes, annulation et file persistante editable.
3. Reprise apres veille/reseau, synchronisation REST, permissions/questions durables, notifications locales protegees, et tests Android de cycle de vie.
4. Agents, skills, commandes, modeles/variantes, providers, OAuth poll-based, MCP, outils, todos et parametres de serveur/configuration.
5. Fichiers, recherche/symboles, statut Git, diff/revue par fichier, undo/redo, commentaires locaux, export assaini et partage explicite.
6. PTY distant experimental, workspaces/sync/control-plane derriere capability flags, puis ecrans avances uniquement lorsque le serveur les supporte.
7. Dictee locale Android/Linux, gestion explicite des modeles Sherpa et audio memoire; Web typed unavailable sous la meme facade `VoiceEngine`.
8. Parite Linux/Web : panneaux redimensionnables, palette/raccourcis, fenetres/deep links, ouverture de fichiers/IDE quand possible, Web HTTPS et cache restreint.
9. Accessibilite, benchmarks de charge, CI Android/Linux/Web, tests de compatibilite serveur/reverse proxy et verification de tous les criteres d'acceptation ci-dessus.

## Decisions a confirmer avant implementation

- Nom de domaine HTTPS prive et reverse proxy pour le client Web.
- Version et mode d'authentification actuels d'OpenCode.
- Politique de conservation locale par defaut, notamment pour Android/Linux.
- Sherpa INT8 beat Whisper and FP32 in measurements on Pixel 5/6a; FP32 did not improve WER and cost model size and memory, while Omnilingual offline was not viable. These measurements motivate the current choice without promising universal results.

## Sources de recherche

- OpenCode documentation et API serveur : <https://opencode.ai/docs/server/>
- OpenCode Web/Desktop source : <https://github.com/anomalyco/opencode/tree/dev/packages/app> et <https://github.com/anomalyco/opencode/tree/dev/packages/desktop>
- OpenCode protocol et fonctionnalites v2 : <https://github.com/anomalyco/opencode/tree/dev/packages/protocol>, <https://github.com/anomalyco/opencode/tree/dev/specs/v2>
- Problemes UX ayant informe les criteres d'acceptation : [#17769](https://github.com/anomalyco/opencode/issues/17769), [#35895](https://github.com/anomalyco/opencode/issues/35895), [#8501](https://github.com/anomalyco/opencode/issues/8501), [#4821](https://github.com/anomalyco/opencode/issues/4821), [#31195](https://github.com/anomalyco/opencode/issues/31195), [#21914](https://github.com/anomalyco/opencode/issues/21914), [#33137](https://github.com/anomalyco/opencode/issues/33137).
