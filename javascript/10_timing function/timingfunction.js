// ! setTimeout()
// setTimeout is a function that allows you to execute a piece of code after a specified delay (in milliseconds). It takes two arguments: the function to execute and the delay in milliseconds.
// It returns a unique identifier that can be used to cancel the timeout using clearTimeout().
console.log("start");


setTimeout(()=>{
    console.log("I am setTimeout");
    
},2000);

console.log("middle");

let wish=()=>{
    console.log("Happy Birthday🎂🎂🎂🎂");
    
}

let b=setTimeout(wish,600);

let sorry=()=>{
    console.log("I am Sorry");
    
}

// ! setInterval()
// setInterval is a function that allows you to repeatedly execute a piece of code at specified intervals (in milliseconds). It takes two arguments: the function to execute and the interval in milliseconds.
// It returns a unique identifier that can be used to cancel the interval using clearInterval().
let a=setInterval(sorry,1000)

console.log("end");

// ! clearTimeout()
// clearTimeout is a function that allows you to cancel a timeout that was previously set using setTimeout(). It takes the unique identifier returned by setTimeout() as an argument.
// In this case, we are canceling the timeout that was set to execute the wish function.
clearTimeout(b)

// ! clearInterval()
// clearInterval is a function that allows you to cancel an interval that was previously set using setInterval(). It takes the unique identifier returned by setInterval() as an argument.
// In this case, we are canceling the interval that was set to execute the sorry function.
clearInterval(a)




