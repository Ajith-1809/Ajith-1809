let getData = async () => {
    try {
        let response = await fetch('https://fakestoreapi.com/products');
        let data = await response.json();

        data.map((item) => { // Iterate through each item in the data array.
            console.log(item.title);
            console.log(item.price);
            console.log(item.rating.rate);
            console.log("------------------------------------");

            let list = document.createElement('li');
            list.innerHTML = `<h3>${item.title}</h3>`
           let ol = document.querySelector('ol');
           ol.appendChild(list);
        });
    } catch (e) {
        console.log(e);
    }
}
getData();
// Output will be the response object and the data fetched from the API