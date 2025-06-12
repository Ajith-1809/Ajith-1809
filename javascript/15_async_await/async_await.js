let getData = async () => {// This function fetches data from a fake store API
    // and logs the response object and the data to the console.
    try {// Using async/await to handle asynchronous operations.

        let response = await fetch('https://fakestoreapi.com/products');
        console.log(response);
        
        let data = await response.json();
        console.log(data);
    } catch (e) {
        console.log(e);
    }
}
getData();
// Output will be the response object and the data fetched from the API