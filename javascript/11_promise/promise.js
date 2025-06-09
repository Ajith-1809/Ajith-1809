// ! Promise()

// Promise is one javascript object, we can create promise using new keyword.(let p = new Promise)

let p = new Promise((resolve, reject)=>{
    let isExam=true;
    if (isExam) {
        resolve("yes you have exam....")
    }
    else{
        reject("no exam..")
    }
});

console.log(p);

p.then((res)=>{
    console.log(res);
    
})
.catch((err)=>{
    console.log(err);
    
})
.finally(
    console.log("Promise has created...")
)


let p1 = new Promise((resolve, reject)=>{
    resolve("I an resolve...")
    reject("I am reject...")
})

console.log(p1);

p1.then((res1)=>{
    console.log(res1);
})
.catch((err1)=>{
    console.log(err1);
    
})

