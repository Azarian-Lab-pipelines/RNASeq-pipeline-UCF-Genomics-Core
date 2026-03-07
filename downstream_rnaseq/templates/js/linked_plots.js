// linked_plots.js
// Cross-plot linking: click pathway bar -> highlight genes in volcano
// Inspired by Plasmidsaurus interactive report features

document.addEventListener('DOMContentLoaded', function() {
  setTimeout(function() {
    // Find all volcano-pathway plot pairs
    document.querySelectorAll('[id^="pathway-plot-"]').forEach(function(pathwayDiv) {
      var contrastId = pathwayDiv.id.replace('pathway-plot-', '');
      var volcanoDiv = document.getElementById('volcano-plot-' + contrastId);

      if (!volcanoDiv || !pathwayDiv) return;

      pathwayDiv.on('plotly_click', function(data) {
        var point = data.points[0];
        var geneString = point.customdata;
        if (!geneString) return;

        var pathwayGenes = geneString.split('/').map(function(g) { return g.trim(); });
        var pathwayName = point.y;

        var volcanoData = volcanoDiv.data;
        volcanoData.forEach(function(trace, traceIdx) {
          if (!trace.text || !Array.isArray(trace.text)) return;
          var newOpacities = trace.text.map(function(ht) {
            var match = ht.match(/<b>(.+?)<\/b>/);
            var gene = match ? match[1] : '';
            return pathwayGenes.includes(gene) ? 1.0 : 0.1;
          });
          var newSizes = trace.text.map(function(ht) {
            var match = ht.match(/<b>(.+?)<\/b>/);
            var gene = match ? match[1] : '';
            return pathwayGenes.includes(gene) ? 12 : 3;
          });
          Plotly.restyle(volcanoDiv, {
            'marker.opacity': [newOpacities],
            'marker.size': [newSizes]
          }, [traceIdx]);
        });

        Plotly.relayout(volcanoDiv, {
          title: 'Volcano — ' + pathwayName + ' (' + pathwayGenes.length + ' genes highlighted)'
        });
      });

      volcanoDiv.on('plotly_doubleclick', function() {
        Plotly.relayout(volcanoDiv, { title: 'Volcano Plot (double-click to reset)' });
        var volcanoData = volcanoDiv.data;
        volcanoData.forEach(function(trace, traceIdx) {
          if (!trace.text) return;
          var resetOpacity = trace.text.map(function() { return 0.6; });
          var resetSize = trace.text.map(function() { return 5; });
          Plotly.restyle(volcanoDiv, {
            'marker.opacity': [resetOpacity],
            'marker.size': [resetSize]
          }, [traceIdx]);
        });
      });
    });
  }, 3000);
});
