let version = "0.0.4";
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
        // 1 is the id for Status (logged in or not)
        // 2 is the id for Affiliation (virginia.edu)
        let status = document.querySelector('.log-in-out').textContent.includes('Sign out');
        let affiliation = status? document.querySelector('.log-in-out').textContent.replace(/.*\@(.*) \|.*/,'$1').trim(): "none";
        document.querySelector('uvalib-analytics').setAttribute('variables',JSON.stringify({
            '1': status? "authenticated":"none",
            '2': affiliation
        }));
        loadModule('uvalib-analytics.js');
    });
});
