let fetchData = fetch('https://fakestoreapi.com/products')
console.log(fetchData);

fetchData // This fetch call returns a promise that resolves to the response object
  .then((data) => { // Once the promise resolves, we log the response object to the console
    // The response object contains information about the HTTP response, such as status and headers.
    console.log(data);

    let jsondata = data.json();
    console.log(jsondata);

    jsondata // The json() method is called on the response object to parse the JSON data
    .then((fd) => { // Once the JSON data is parsed, we log it to the console
        // The parsed data is now available as a JavaScript object or array, depending on the structure of the JSON.

        console.log(fd);
        
        
    }).catch((err) => { // If there is an error during the JSON parsing, it will be caught here
        // The error will be logged to the console.
        console.log(err);
        
        
    });
    
    
  })
    .catch((error) => { // If there is an error during the fetch operation, it will be caught here
    // The error will be logged to the console.
      console.log(error);
    })