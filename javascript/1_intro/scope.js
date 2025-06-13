// ! global scope - var 
// ! script scope - let,const

var a=10; 
let b=20;
const c=30;

console.log(a);
console.log(b);
console.log(c);


// ! block scope - {}

{
var aa=100;
let bb=200;
const cc=300;

console.log(aa);
console.log(bb);
console.log(cc);
}

// ! functions - local scope

