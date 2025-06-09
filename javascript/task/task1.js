// ! Destructuring
// ? Destructuring is a process of extracting data from an array or object and storing it into variables.

// ? -it reduces the code complexities.
// ? -it increases readability.
// ? -for arrays : we can use any variable names.
// ? -for objects : we must use the exact key name (case-sensitive).

// let arr = [1,2,3,4,5]
// let[a,b,c,d,e] = arr;

// console.log(a,b,c,d,e);

// let [,,,d,] = arr

// console.log(d);

// let arr = [100,2,300,9,8,1000,10,5]
// let [,,c,,e,,g,h] = arr
// console.log(c,e,g,h);

// let arr = [1,2,3,[100,200],4,[300]]
// let [,,,[a,b],,[f]] = arr
// console.log(a,b,f);


// let arr = [1,2,[100,200,300[7,8,9],400,500],[[[1000,10],7],8,10]]
// let [,,[a,b,,[,,c],,d],[[[e],f],,g]] = arr
// console.log(a,b,c,d,e,f,g);


// let obj = {
//     name : "virat",
//     age : 37,
//     team : "india",
//     no : 18,
//     role : "allrounder",
//     address : {
//         loc : "qspiders",
//         city : "chennai",
//         pin : 600026
//     }
// }

// let {name,age,team,no,role} = obj
// console.log(name,age,team,no,role);

// let {name,team} = obj
// console.log(name,team);

// let {name,team,address:{loc,city,pin}} = obj
// console.log(name,team,loc,city,pin);
// console.log(address); ---------> //! error
// let {name,team,address:{loc,city,pin},address} = obj
// console.log(address);


var obj ={
    name : "xyz",
    id : 123,
    skills : {
        front_end : {
        front : "HTML",
        second : "CSS",
    },
    allskills : {
        one : [
            {
                majorskills : [
                    {
                        proficient : "java",
                    },
                    {
                        moderate : "SQL",
                    },
                 ],
            },
        ],
        two : [
            {
                minorskill : [
                    {
                        duration : 40,
                    },
                ],
            },
        ],
    },
},
}


var{skills:{allskills:{one:[{majorskills:[{proficient},{moderate}]}],two:[{minorskill:[{duration}]}]}}}=obj
console.log(proficient,duration,moderate);
