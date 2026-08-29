# Controllo di prosa

Dal menu **Vista › Evidenzia i problemi di prosa**, o accendendolo per tutti i
nuovi documenti in **Preferenze › Resa grafica › Scrittura**.

Sottolinea sei categorie con colori diversi, e mette il conteggio nel
sottotitolo della finestra. Non corregge niente: segnala e basta.

Le liste stanno in `MacDown/Resources/Data/prose-issues.json` e si possono
allungare o tradurre senza ricompilare.

## Italiano

Il sistema è stato praticamente riscritto al fine di migliorare
significativamente le prestazioni. Credo che potrebbe essere molto utile
utilizzare diversi approcci, per quanto riguarda la maggior parte dei casi
d'uso.

Va detto che, in un certo senso, la soluzione appare sostanzialmente
adeguata, anche se forse sarebbe opportuno effettuare ulteriori verifiche.

## Inglese

This is actually a very significant improvement. I believe we should
probably do it in order to move faster, due to the fact that the current
approach is somewhat suboptimal.

It should be noted that the results were basically quite good.

## Raddoppi

Le ripetizioni vere vengono segnalate:

Questa questa è una ripetizione. E anche the the duplicated word.

I raddoppi voluti no, perché in italiano sono normali:

Piano piano le cose vanno via via meglio, e man mano che procediamo quasi
quasi ci arriviamo. He had had enough of that that sentence.

## Dove non guarda

Dentro il codice non segnala nulla, né in linea — `molto praticamente
significativo` — né in blocco:

```
Questo testo è praticamente molto significativo
e credo che potrebbe essere utilizzato.
```

## Le sei categorie

| Categoria | Cosa segnala | Esempio |
|---|---|---|
| Qualifiers | rafforzativi che non aggiungono nulla | molto, praticamente, davvero |
| Weasel words | valutazioni non sostanziate | significativo, adeguato, utilizzare |
| Hedging | attenuazioni | forse, credo che, potrebbe essere |
| Wordiness | perifrasi allungate | al fine di, per quanto riguarda |
| Passive tells | spie del passivo | è stato, viene effettuato |
| Repeated words | parole raddoppiate | questa questa |
