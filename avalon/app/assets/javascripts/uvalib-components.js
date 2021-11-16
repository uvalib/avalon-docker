let version = "0.0.2";
let baseUrl = `https://unpkg.internal.lib.virginia.edu/v${version}/`;
let loadModule = (url)=>{
        let script = document.createElement('script');
        script.setAttribute('type','module');
        script.setAttribute('src',`${baseUrl}${url}`);
        document.head.appendChild(script);
    };

loadModule('uvalib-analytics.js');
loadModule('uvalib-header.js');
loadModule('uvalib-footer.js');