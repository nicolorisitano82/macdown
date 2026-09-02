# Plug-in

Un plug-in è un bundle `.plugin` in
`~/Library/Application Support/MacDown/PlugIns/`. MacDown Next lo carica
all'avvio, istanzia la sua classe principale e aggiunge una voce al menu
**Plug-ins**.

Da **Plug-ins › Gestisci plug-in…** puoi vedere quelli installati,
disattivarne uno senza cancellarlo, aggiungerne e rimuoverne.

## Cosa deve fare la classe principale

Tre metodi, tutti opzionali:

| Metodo | Quando | A cosa serve |
|---|---|---|
| `-name` | all'avvio | il testo della voce di menu |
| `-plugInDidInitialize` | all'avvio | preparazione, se serve |
| `-run:` | alla scelta della voce | il lavoro; restituisce `BOOL` |

Il bundle deve dichiarare `NSPrincipalClass` nel suo `Info.plist`.

## Come raggiungere il documento

Un plug-in non viene compilato insieme a MacDown Next e non conosce le sue
classi. Il modo pulito è la catena dei responder: mentre scrivi, l'editor è
il first responder.

```objectivec
NSResponder *r = [NSApp keyWindow].firstResponder;
if ([r isKindOfClass:[NSTextView class]]) {
    NSTextView *editor = (NSTextView *)r;
    [editor insertText:@"ciao" replacementRange:editor.selectedRange];
}
```

Passando da `insertText:replacementRange:` l'inserimento rispetta la
selezione e finisce nella pila di annullamento, quindi ⌘Z lo toglie.

## L'esempio

`LoremIpsum/` è un plug-in completo in un solo file: chiede tipo e numero di
paragrafi e li inserisce nel punto del cursore. Per costruirlo e
installarlo:

    ./LoremIpsum/build.sh --install

Poi riavvia MacDown Next, perché i plug-in vengono letti una volta sola.

Non serve un target Xcode: un `.plugin` è un Info.plist più un binario
compilato con `-bundle`, ed è quello che fa lo script.
