// Performs a GET request to the provided URL
// Returns a promise for a response object that has these properties:
//     responseHeaders - String, with CRLF line terminators.
//     responseText
//     status
//     statusText
async function PDA_httpGet(url) {
    await __PDA_platformReadyPromise;
    return window.flutter_inappwebview.callHandler("PDA_httpGet", url);
}

// Performs a POST request to the provided URL
// The expected arguments are:
//     url
//     headers - Object with key, value string pairs 
//     body - String or Object with key, value string pairs. If it's an object,
//            it will be encoded as form fields
// Returns a promise for a response object that has these properties:
//     responseHeaders: String, with CRLF line terminators.
//     responseText
//     status
//     statusText
async function PDA_httpPost(url, headers, body) {
    await __PDA_platformReadyPromise;
    return window.flutter_inappwebview.callHandler("PDA_httpPost", url, headers, body);
}

// Performs a network request with a similar API as fetch
// 
// Basic implmentation is based upon MDN's fetch reference: https://developer.mozilla.org/en-US/docs/Web/API/Fetch#syntax
async function PDA_fetch(resource, options = {}) {
    function pathParent(path) {
        return path.split("/").slice(0, -1).join("/");
    }

    await __PDA_platformReadyPromise;

    return new Promise((resolve, reject) => {
        if (typeof resource !== Request && (resource === null || !resource.hasOwn("toString"))) {
            // The resource must be a string or any other object with a stringifier... or a request object
            // Might not comply with MDN's reference
            //
            // Firefox allows `null` as the resource
            // while null is not an object so it does not have the toString attribute
            reject(new TypeError("Invalid resource type. Must be a Request or String object or another object with a stringifier."));
            return;
        }

        try {
            const parsedRequest = typeof resource === Request ? resource : new Request(resource, options);
            const flutterResponse = window.flutter_inappwebview.callHandler("PDA_fetch", parsedRequest.url, {
                body: parsedRequest.text(),
                cache: parsedRequest.cache,  // not used
                credentials: parsedRequest.credentials,  // not used
                headers: parsedRequest.headers,
                integrity: parsedRequest.integrity,  // not used
                method: parsedRequest.method,
                mode: parsedRequest.mode,  // not used
                redirect: parsedRequest.redirect,
                referrer: parsedRequest.referrer, // not used
                referrerPolicy: parsedRequest.referrerPolicy, // not used
                signal: parsedRequest.signal,  // not used
            });
        } catch (err) {
            reject(err);
            return;
        }

        // Integrity check
        // Valid algorithms: SHA-256, SHA-384, SHA-512
        //  - W3C Subresource Integrity (section 3.1)
        //  - Conformant user agents MUST support the SHA-256, SHA-384, and SHA-512 cryptographic hash functions for use as part of a request’s integrity metadata and MAY support additional hash functions.

        try {
            const finalResponse = new Response(flutterResponse.body, {
                status: flutterResponse.status,
                statusText: flutterResponse.statusText,
                headers: flutterResponse.headers,
            });

            return finalResponse;
        } catch (err) {
            reject(err);
            return;
        }
    });
}
