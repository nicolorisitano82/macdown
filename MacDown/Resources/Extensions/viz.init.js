// Graphviz bootstrap.
//
// A fenced block whose language is one of Graphviz's layout engines is
// treated as DOT source and laid out by viz.js, which is Graphviz itself
// compiled to JavaScript.
//
// The version of this file that shipped before had the same two faults the
// mermaid one did. It walked up from the <code> to the <pre> and then to the
// <pre>'s parent — the body — and assigned innerHTML there, so rendering a
// single graph wiped out the rest of the document. And it bound to the load
// event, which fires once: MacDown refreshes the preview by replacing the
// body, and that runs no scripts, so every graph reverted to a code block as
// soon as you typed. Both are handled the way they are for mermaid.
//
// Written in ES5 on purpose, to match the rest of the bundled extensions.

(function () {

  // Graphviz picks a layout by engine, and each is spelled as a fence
  // language: ```dot for the hierarchical one, ```neato for spring layout,
  // and so on.
  var ENGINES = ["circo", "dot", "fdp", "neato", "osage", "twopi"];

  // Graphviz sizes a graph in inches and viz.js turns that into a width the
  // pane rarely matches. Big graphs are what the zoom is for; this is only
  // the fallback for a graph whose SVG carries no usable width.
  var LAYOUT_WIDTH = 1200;

  // The fence arrives as <pre><code class="language-dot">. Swapping the <pre>
  // out for a plain container drops the code block's frame and background,
  // which would otherwise box the finished graph.
  function containerFor(block) {
    var target = block;
    if (block.tagName === "CODE"
        && block.parentElement
        && block.parentElement.tagName === "PRE") {
      target = block.parentElement;
    }
    if (!target.parentNode)
      return null;

    var holder = document.createElement("div");
    holder.className = "macdown-diagram";
    target.parentNode.replaceChild(holder, target);
    return holder;
  }

  function renderOne(block, engine, stateKey) {
    var source = block.innerText || block.textContent;
    var holder = containerFor(block);
    if (!holder)
      return;

    // A graph being typed is malformed most of the time, and viz.js reports
    // that by throwing. Showing the message beats losing the document.
    try {
      holder.innerHTML = Viz(source, { engine: engine, format: "svg" });
      var svg = holder.querySelector("svg");
      if (svg && window.MacDownMakeZoomable)
        MacDownMakeZoomable(holder, svg, stateKey, LAYOUT_WIDTH);
    } catch (e) {
      holder.className = "macdown-diagram macdown-diagram-error";
      holder.style.height = "";
      holder.textContent = String(e && e.message ? e.message : e);
    }
  }

  function renderAll() {
    if (typeof Viz === "undefined")
      return;

    for (var e = 0; e < ENGINES.length; e++) {
      var engine = ENGINES[e];
      var blocks = document.querySelectorAll("code.language-" + engine);
      for (var i = 0; i < blocks.length; i++) {
        renderOne(blocks[i], engine, engine + i);
      }
    }
  }

  // MacDown calls this after refreshing the preview, since the refresh
  // replaces the body without running any script. window keeps its
  // properties across that, so this function is still here afterwards.
  window.MacDownRenderGraphviz = renderAll;

  if (document.readyState === "complete"
      || document.readyState === "interactive") {
    renderAll();
  } else {
    window.addEventListener("load", renderAll, false);
  }
})();
