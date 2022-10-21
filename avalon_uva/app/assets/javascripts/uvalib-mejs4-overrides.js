$(document).ready(function() {
  var searchField = document.getElementById('searchField')
  if(searchField) {
    searchField.addEventListener('keydown', function(e){
      e.stopPropagation();
    }, false);
  }
});