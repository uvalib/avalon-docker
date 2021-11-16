let version = "0.0.2";
let baseUrl = `https://unpkg.internal.lib.virginia.edu/v${version}/`;
let loadModule = (url)=> new Promise((resolve)=>{
    let script = document.createElement('script');
    script.type = 'module';
    script.onload = resolve;
    script.src = `${baseUrl}${url}`;
    document.head.appendChild(script);
});

// Load up the header first as it most likely is holding up viewable rendering
loadModule('uvalib-header.js').then(()=>{
    // Then go ahead and load up the footer so it will be there when they scroll down
    loadModule('uvalib-footer.js').then(()=>{
        // With those visible things out of the way, go ahead and load up the analytics tracking
        loadModule('uvalib-analytics.js');
    });
});
