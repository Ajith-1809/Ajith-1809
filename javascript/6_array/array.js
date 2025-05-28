// ! Array in JavaScript

// Array is linear data structure where multiple value can be stored in continuous manner.

// In javascript array will be store both homogeneous and heterogeneous also.

let array=[10,20,30,40,50]

// ! How to access array element
console.log(array[2]);  //30

// ! How to know the lenth of the array
console.log(`The lenth of the array is ${array.length}`);

// ! Array methods

// ! 1.push()

// It is used to add any element at the end of the array.

// It will return the lenth of the modified array.(lenth after the adding the element)

let arr=[10]
arr.push(20)
arr.push(30)
arr.push(40)
console.log(arr);
console.log(arr.push(50));

// ! 2.pop()

// It is used to remove the any element at the end of the array.(last element)

// It will return the removed element on the output.

let arr1=[10,20,30,40,50]
console.log(arr1);
arr1.pop()
console.log(arr1);
arr1.pop(40)
console.log(arr1);
console.log(arr1.pop(30));

// ! 3.unshift()

// It is used to add the any element at the starting of the array.

// It will return the lenth of the modified array.

let arr2=[10,20,30]
arr2.unshift(40)
console.log(arr2);

// ! 4.shift()

// It is used to remove the any element at the starting of the array.(last element)

// It will return the removed element on the output.

let arr3=[10,20,30,40]
arr3.shift()
console.log(arr3);

// next monday (26/05/2025) there will be webtech mock.

// ! 5.includes()

// It is used to check whether the given element is predent or not in the array.

// If it is present it will return true otherwise it will return false.

let arr4=["html","js","react"]
console.log(arr4.includes("html"));

// ! 6.reverse()

// It is used to reverse the array and it will return one new array.
// This method will modify the original array.

let arr5=[10,20,30,40,50]
let reversearr=arr5.reverse()
console.log(reversearr);
console.log(arr5);

// ! 7.join()

// It is used to convert array into string datatype.

let arr6=['h','e','l','l','o']
let str=arr6.join("")
console.log(str);

// ! reverse string by using in-built methods

let name="javascript"
let conname=name.split("")
let revarr=conname.reverse()
let revstr=revarr.join("")
console.log(revstr);

// ! 8.index()


let teams=['gt','rcp','pk','csk']
console.log(teams.indexOf('csk'));

// ! 9.slice()
// I

// ! 10.splice()

let names=["rohit","virat","rahul","iyer","jadeja","rinku"]
// console.log(names.splice(1,3));
// names.splice(1,2,"csk")
names.splice(1,0,"csk")
console.log(names);


// ! 11.Higher order array method

// It is one higher order array method. It is used to traverse the array.

// It will take one callback function there it can take 3 parameters (element,index,array)

let num=[10,20,30,40,50,60]
num.forEach((element,index,array)=>{
    console.log(element,index);
    
});

// ! add all the elements of the array by using foreach() method

let sum=0
num.forEach((element)=>{
    sum=sum+element
})
console.log(`The sum of the array elements is : ${sum}`);



let a=[10,20,30,40]
let b=[]
a.forEach((ele)=>{
b.push(ele+110)})
console.log(b);

// ! 12.map()

//  It is one higher order method, it is used for traversing the array and if we want to do any operation with the all elements we can do.

//  this method will return one new array.

// it can take 3 parameters. (element, index, array)

let mappedarry=b.map((ele=>{
    return ele;
}))
console.log(mappedarry);

let product=['mobile','laptop','camera']
let mapped=product.map((ele=>{
    return ele.toUpperCase();
}))
console.log(mapped);

// ! elements who are greater than 20, by using foreach()

// let aa=[10,20,30,40]

// let greater=a.map((ele)=>{
//     if (ele>20) {
//         return ele
//     }
// })
// console.log(greater);




// ! 13.filter()

// it is higher order method array, it is used to traverse the array and it checks the condition if the condition the true then it will return the new array.

// it can take 3 parameters.(element, index, array)

let filterarr=a.filter((ele=>{
    return ele > 20
}))
console.log(filterarr);

// ! 14.reduce()

let add=a.reduce((acc,ele)=>{
    return acc+ele
},0)
console.log(add);

let mul=a.reduce((acc,ele)=>{
    return acc*ele
},1)
console.log(mul);



let prices=[200,400,500,600,100]

// find the value who are greater than 400 then add 200 with each value then add those values and tell me what is the total price.

// 500,600
// 700,600
// 1500

let great=prices.filter((ele)=>{
    return ele > 400
    
})
// console.log(great);

let add1=great.map((ele)=>{
    return ele + 200
})
// console.log(add1);

let add2=add1.reduce((acc,ele)=>{
    return acc + ele
})
console.log(add2);


// ! 15.sort()

let ratings=[5,6,4,2,3,1]
console.log("asscending order");
let ass=ratings.sort((a,b)=>a-b)
console.log(ass);

console.log("desscending order");
let dec=ratings.sort((a,b)=>b-a)
console.log(dec);



let a1=[10,20,30,40]
let b1=a.map((ele)=>{
    return ele
})
console.log(b1);

if (undefined) { //false values: "", 0,-0,undefined,null,nan
    console.log("hello");
    
}
else; console.log('hi');






