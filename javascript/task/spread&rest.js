// ! Spread and Rest

// ? These two operators are declared by using (...)
// ? Spread and Rest operators look alike but both are different.

// ! Spread

// ? Spread operator is used to unpack the value from an array and objects.
// ? It allows us to copy the elements/properties in an efficient way.

// ! E.g

// let a1 = [1,2,3,4,5]
// let a2 = [6,7,8,9,10]
// let a3 = [11,12,13,14,15]

// // let a = a1.concat(a2)
// // console.log(a);

// console.log(a1);
// console.log(...a1);
// console.log(...a2);

// let a = [...a1,...a2,...a3];
// console.log(a);

// let obj1 = {
//     name : "dhoni",
//     age : 42
// }

// let obj2 = {
//     isRetaired : false,
//     jerseyNo : 7
// }

// let newobj = {...obj1,...obj2}
// console.log(newobj);

// ! Rest

// ? In function as a parameter (...) is called Rest.
// ? In function as a call (...) is called Spread.

// ? L.H.S = R.H.S
// ! (...) = (...)
// ? Spread = Rest


// function add(a,b,...c){
//     console.log(a);  //1
//     console.log(b);  //2
//     console.log(c);
//     console.log(a+b);
// }
// add(1,2,3,4,5,6,7)

let arr = [1,2,3,4,5,6]
let [a,b,...c] = arr

console.log(a);
console.log(b);
console.log(c);







