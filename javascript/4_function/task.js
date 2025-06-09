let radius=[5,10,15,20]

const bi = 3.14

let area = r =>{
   let a = r.map(e => e*e*bi);
        return a;
};

console.log(area(radius));



