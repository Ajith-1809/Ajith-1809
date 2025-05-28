// ! How to create object

let student = {
    sname:"rohit",
    age:10,
    isPlayer:true,
    sub:["html","css","js"],
    do:()=>{
        console.log("eat sleep study");
        
    },

    add:{
        city:"chennai",
        pin:600026
    }
}
console.log(student);


// ! How to access object property

console.log(`The name of the student is ${student.sname}`);
console.log(`The age of student is ${student.age}`);
console.log(`city is ${student.add.city}`);

// ! How to add any new element

student.phno=1234567
console.log(student);

// ! How to update any element value

student.isPlayer=false
console.log(student);

// ! How to delete any value

delete student.age
console.log(student);

let obj=student.sub.forEach(element => {
    console.log(element.toUpperCase());
    
});

// ! Object methods
// ! 1.Object.keys()
// This method is used to return all the keys of the object in the form of array.

let keys=Object.keys(student)
console.log(keys);

// ! 2.Object.values()

// this method is used to return all the values of the object in the form of array.

let values=Object.values(student)
console.log(values);

// ! 3.Object.entries()

// it will return one array where all the key and value will store in separate one one array.

let key_value=Object.entries(student)
console.log(key_value);

// ! 4.Object.freeze()

// this method will make the object frozen where we can not add/modify/delete any element from the object.

let ob1={
    sname:"rahul",
    age:10
}
console.log(ob1);

Object.freeze(ob1)

console.log("after freeze");

ob1.age=16
console.log(ob1);

// ! 5.Object.isFrozen()

// it is used to check whether any object is frozen or not.

// if it is frozen it will return true else it will return false.

console.log(Object.isFrozen(ob1));  // true
console.log(Object.isFrozen(student));  // false

// ! 6.Object.seal()

// it is also similar to object.freeze() method, we can't add and we can't delete but we can modify the value.

let ob2={
    sname:"iyer",
    age:15
}
console.log(ob2);

Object.seal(ob2)

console.log("after using object.seal()");

ob2.phno=234556666  // we can't add

delete ob2.age   // we can't delete

ob2.age=16  // we can modify

console.log(ob2);

// ! 7.Object.isSealed()

// it is used to check whether any object is sealed or not.

// if it is sealed it will return true else it will return false.

console.log(Object.isSealed(ob1));  // true
console.log(Object.isSealed(student));  // false

// ! 8.Object.assign()

let ob3={
    sname:"rahul",
    age:16
}

let ob4={
    city:"chennai",
    pin:600026
}

let oba=Object.assign({},ob3,ob4)
console.log(oba);
console.log(ob3);
console.log(ob4);

// ! 9.object.hasOwnProperty()

// this method is used to know any property is present or not and it will return boolean value.

console.log(ob4.hasOwnProperty("city"));
console.log(ob4.hasOwnProperty("sname"));









