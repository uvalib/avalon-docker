$(document).ready(function() {
  document.getElementById('searchField').addEventListener('keydown', function(e){
    e.stopPropagation();
  }, false);
});