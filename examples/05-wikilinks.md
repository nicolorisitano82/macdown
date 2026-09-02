# WikiLinks

Un riferimento fra due parentesi quadre diventa un collegamento al
documento vicino con quel nome. Serve per tenere insieme una cartella di
appunti senza scrivere percorsi.

Si accende in **Preferenze › Resa grafica › Scrittura**.

## Riferimenti che esistono

Questi puntano ad altri file di questa cartella, e sono cliccabili:

- [[01-markdown]] — markdown ed estensioni
- [[02-mermaid]] — diagrammi
- [[04-matematica]] — formule

Cliccandoli il documento si apre in MacDown Next, non nel browser.

## Riferimenti che non esistono ancora

Un riferimento a un documento che non c'è resta visibile ma è segnato come
mancante, così vedi subito cosa hai citato e non hai ancora scritto:

- [[09-plugin]]
- [[10-scorciatoie]]

È il modo normale di lavorare con appunti collegati: scrivi il riferimento
mentre ti viene in mente, il file lo crei dopo.

## Con un'etichetta

Si può scrivere un testo diverso dal nome del file, separandolo con una
barra verticale:

- [[01-markdown|le estensioni Markdown]]
- [[03-graphviz|come si disegnano i grafi]]

## Dentro il codice non succede nulla

Un riferimento dentro un blocco di codice resta testo:

```
Questo [[non diventa]] un collegamento.
```

E nemmeno in linea: `[[neppure questo]]`.
