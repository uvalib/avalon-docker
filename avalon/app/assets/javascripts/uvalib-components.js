let uvalib_analytics_setup = ()=>{
    let version = "0.0.4";
    let baseUrl = `https://unpkg.internal.lib.virginia.edu/v${version}/`;
    let loadModule = (url)=> new Promise((resolve)=>{
        let script = document.createElement('script');
        script.type = 'module';
        script.onload = resolve;
        script.src = `${baseUrl}${url}`;
        document.head.appendChild(script);
    });

    // events - [category, action, name, value]
    let trackEvent = (events)=>{
        if (Array.isArray(events) && events.length>0) {
            document.dispatchEvent(new CustomEvent("uvalib-analytics-event", {
                detail: {event:events},
                bubbles: true
            }));
        }
    }

    // Load up the header first as it most likely is holding up viewable rendering
    loadModule('uvalib-header.js').then(()=>{
        // Then go ahead and load up the footer so it will be there when they scroll down
        loadModule('uvalib-footer.js').then(()=>{
            // With those visible things out of the way, go ahead and load up the analytics tracking
            // 1 is the id for Status (logged in or not)
            // 2 is the id for Affiliation (virginia.edu)
            let status = document.querySelector('.log-in-out').textContent.includes('Sign out');
            let affiliation = status? document.querySelector('.log-in-out').textContent.replace(/.*\@(.*) \|.*/,'$1').trim(): "none";
            console.info(`status: ${status}`);
            console.info(`affiliation: ${affiliation}`);
            document.querySelector('uvalib-analytics').setAttribute('variables',JSON.stringify({
                '1': status? "authenticated":"none",
                '2': affiliation
            }));
            loadModule('uvalib-analytics.js').then(()=>{
                // Analytics loaded, lets track some events
                let videoPlayer = document.querySelector('mediaelementwrapper');
                if (videoPlayer) {
                    let title = document.title.replace(/\- Avalon.*/,"").trim();
                    // Video timeupdate - The playing position has changed (like when the user fast forwards to a different point in the media)
                    videoPlayer.addEventListener('timeupdate',()=>{ trackEvent(['media','timeupdate',title,affiliation]); });
                    // Video seeked - The seeking attribute is set to false indicating that seeking has ended
                    videoPlayer.addEventListener('seeked',()=>{ trackEvent(['media','seeked',title,affiliation]); })
                    // Video playing - The media actually has started playing
                    videoPlayer.addEventListener('playing',()=>{ trackEvent(['media','playing',title,affiliation]); })
                    // Video pause - The media is paused either by the user or programmatically
                    videoPlayer.addEventListener('pause',()=>{ trackEvent(['media','pause',title,affiliation]); })
                    // Video ended - The media has reach the end
                    videoPlayer.addEventListener('ended',()=>{ trackEvent(['media','ended',title,affiliation]); }) 
                    // Video volume changed - Volume is changed (including setting the volume to "mute")
                    videoPlayer.addEventListener('volumechange',()=>{ trackEvent(['media','volumechange',title,affiliation]); })                
                }
                // Searched performed
            });
        });
    });
}; uvalib_analytics_setup();
