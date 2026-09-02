# Markdown e le estensioni

Il markdown di base funziona sempre. Le estensioni si accendono in
**Preferenze › Markdown**, e questo documento le usa tutte, così vedi subito
quali hai attive: quello che resta testo grezzo nell'anteprima è spento.

## Testo

Corsivo con *asterischi*, grassetto con **doppi asterischi**, entrambi con
***tripli***.

Con **Intra-word emphasis** acceso, anche in mezzo a una parola:
super*cali*fragilistico.

Con **Strikethrough**: ~~questa frase è cancellata~~.

Con **Highlight**: ==questa è evidenziata==.

Con **Underline**: _questa è sottolineata_ invece che in corsivo.

Con **Superscript**: 2^10 fa 1024, e l'area è πr^2.

Con **Smartypants**: "le virgolette diventano curve" -- e i trattini
diventano lineette --- come questa.

## Liste

- Punto uno
- Punto due
  - Annidato
- Punto tre

1. Primo
2. Secondo
3. Terzo

Con **Task list syntax** acceso:

- [x] Cosa fatta
- [ ] Cosa da fare
- [ ] Un'altra cosa da fare

## Citazioni

> Una citazione su una riga.
>
> Con **Quote** acceso, anche ""questo"" diventa una citazione in linea.

## Codice

Codice in linea: `NSString *nome = @"MacDown Next";`

Con **Fenced code block** acceso, un blocco con il linguaggio dichiarato —
e con **Evidenzia la sintassi** acceso in Preferenze › Resa grafica, colorato:

```objectivec
- (NSString *)saluta:(NSString *)nome
{
    if (!nome.length)
        return @"Ciao.";
    return [NSString stringWithFormat:@"Ciao, %@.", nome];
}
```

```python
def fibonacci(n):
    a, b = 0, 1
    for _ in range(n):
        yield a
        a, b = b, a + b
```

## Tabelle

Con **Table** acceso, e con gli allineamenti per colonna:

| Componente | Stato | Righe |
|:-----------|:-----:|------:|
| Editor     | fatto | 1 240 |
| Anteprima  | fatto |   890 |
| Export     | in corso | 610 |

Le tabelle sopravvivono anche all'esportazione in Word: diventano tabelle
vere, non testo separato da tabulazioni.

## Collegamenti

Un [collegamento normale](https://github.com/nicolorisitano82/macdown).

Con **Autolink** acceso, anche un indirizzo nudo diventa cliccabile:
https://github.com/nicolorisitano82/macdown

## Note a piè di pagina

Con **Footnote** acceso, questa frase ha una nota[^1] e anche questa[^lunga].

[^1]: Le note finiscono in fondo al documento, numerate.
[^lunga]: L'etichetta può essere una parola invece che un numero.

## Righe

Tre trattini fanno una riga orizzontale:

---

E qui finisce.
