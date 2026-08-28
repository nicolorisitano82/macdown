# Diagrammi mermaid

Un blocco di codice con `mermaid` come linguaggio diventa un disegno. Il
tema segue l'aspetto del sistema: in modalità scura i diagrammi sono scuri.

La libreria viene caricata solo per i documenti che contengono un
diagramma, quindi tenere la funzione accesa non rallenta nulla altrove.

## Diagramma di flusso

```mermaid
graph TD
    A[Editor] --> B{Renderer}
    B -->|markdown| C[hoedown]
    B -->|diagrammi| D[mermaid]
    C --> E[Anteprima]
    D --> E
```

## Sequenza

```mermaid
sequenceDiagram
    participant U as Utente
    participant M as MacDown
    participant W as WebView
    U->>M: digita
    M->>M: rende il markdown
    M->>W: aggiorna la pagina
    W-->>U: anteprima
```

## Stati

```mermaid
stateDiagram-v2
    [*] --> Inattivo
    Inattivo --> Rendering: modifica
    Rendering --> Inattivo: fatto
    Rendering --> Errore: sintassi non valida
    Errore --> Rendering: correzione
```

## Classi

```mermaid
classDiagram
    class MPDocument {
        +NSString markdown
        +render()
        +exportEpub()
    }
    class MPRenderer {
        +NSArray stylesheets
        +NSArray scripts
    }
    MPDocument --> MPRenderer
```

## Torta

```mermaid
pie title Dove vanno le righe
    "Documento" : 3100
    "Anteprima" : 1200
    "Export" : 980
    "Preferenze" : 400
```

## Zoom

Il gantt qui sotto è largo: alla larghezza del pannello le date si
sovrappongono. Passaci sopra e compaiono i comandi in alto a destra —
oppure pizzica sul trackpad, trascina per spostarti, doppio clic per
tornare alla vista intera.

```mermaid
gantt
    dateFormat YYYY-MM-DD
    title Sviluppo del fork
    excludes weekends

    section Fondamenta
    Base macOS 26        :done, f1, 2026-08-01, 3d
    Chrome della finestra :done, f2, after f1, 4d

    section Anteprima
    Migrazione WKWebView  :done, a1, after f2, 6d
    Diagrammi e zoom      :done, a2, after a1, 5d

    section Esportazione
    Word con tabelle      :done, e1, after a2, 4d
    EPUB 3.3              :active, e2, after e1, 3d
```

## Errori

Un diagramma con sintassi non valida non porta giù la pagina: al suo posto
compare il messaggio dell'errore, e mentre lo stai scrivendo è normale
vederlo.

```mermaid
graph TD
    A[Manca la parentesi
```
