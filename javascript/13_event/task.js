let result = document.getElementById("result");
let form = document.querySelector("form");
form.addEventListener("submit", (e)=>{
    e.preventDefault(); // Prevent the form from submitting and refreshing the page
    // Get the values from the input fields and perform addition
    let number1 = parseInt(document.getElementById("number1").value);
    let number2 = parseInt(document.getElementById("number2").value);
    console.log(number1+number2);
    // Display the result in the result div
    
    result.innerHTML = `<h3>Addition of ${number1} and ${number2} is ${number1 + number2}</h3>`;
})