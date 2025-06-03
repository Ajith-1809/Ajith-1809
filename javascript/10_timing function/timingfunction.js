// ! setTimeout()
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
let a=setInterval(sorry,1000)

console.log("end");

// ! clearTimeout()
clearTimeout(b)

// ! clearInterval()
clearInterval(a)




