// ! Function
// function is a block of code that performs a specific task. It is reusable and can be called multiple times in the program. Functions help to organize code, make it more readable, and reduce redundancy.
// ! How to declare function

function add()
{
    let a=10;
    let b=30;
    let sum=a+b;

    console.log(`The additin of ${a} and ${b} is ${sum}`);
    
}

add();

// ! Function with parameter
// A function can take parameters, which are values passed to the function when it is called. Parameters allow functions to operate on different data without changing the function's code.

function greet(username)
{
    console.log(`good morning ${username}`);
    
}

greet("javascript")

// ! Function with return keyword
// A function can return a value using the return keyword. This allows the function to send a result back to the caller, which can be used later in the program.
// The return statement ends the function execution and specifies the value to be returned.

function multiply(a,b){
    return a*b;
}
let res=multiply(10,2)
console.lw21og(res);

// ! Anonymous Function

// The function does not have any name, that is called anonymous function.


let anonymous=function(){
    console.log("I am anonymous function");
    
}
anonymous()

// ! Arrow function

let arrow=()=>{
    console.log("I am Arrow function");
    
}
arrow()

// ! Find the area of the triangle by using arrow function.

let area=(b,h)=>{
    let sum=1/2*(b*h)
    console.log(`The area of the triangle is ${sum}`);
    
}
area(20,4)

// ! Nested function

// When we are declaring one function inside another function that is called nested function.

let parent=()=>{
    console.log("I am parent function");
    let child=()=>{
        console.log("I am child function");
        
    }
    child()
}
parent()

// ! Lexical scopping function

// If we are taking nested function, inner function can take all the properties of outer function but outer function can not take properties of the inner function. It is called Lexical function.

let outer=()=>{
    let a=10;
    let inner=()=>{
        let b=20;
        console.log(a);
        console.log(b);
    }
    inner()
}
outer()

// ! Higher order function

// Any function that takes another function as parameter that is called higher order function.

// ! Callback function

// The function we are sending as a parameter to the higher order function is called callback function.

let hof = (cb)=>{
    cb()
}

hof (()=>{
    console.log("I am callback function");
})



let addi=(a,b)=>{
    console.log(a+b);
}

let sub=(a,b)=>{
    console.log(a-b);
}

let mul=(a,b)=>{
    console.log(a*b);
}

let calculate =(myfunc,x,y)=>{
    myfunc(x,y)
}

calculate(addi,10,20)
calculate(sub,20,10)
calculate(mul,2,3);

// ! (IIFE) Immediate invoke Function Expression

(
    function (a,b) {
        console.log("I am immediate invoke function expression");
        console.log(a+b);
    }
)(2,2);

 