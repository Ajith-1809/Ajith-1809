// JSON (Javascript Object Notation) is a lightweight data-interchange format.

// that is easy for humans to read and write, and easy for machines to parse and generate.

// ! Advantages of JSON

// ? Human-Readable:

//  JSON's structure is easy for developers to understand and write.

// ? Light-weight:

//  JSON is a minimal format that reduces the size of the data being transmitted.

// ? Language-Independent:

//  JSON can be used with many programming languages.
// Includes javascript, python, java, etc.

let ob={
    sname:"samm",
    age:20,
    phno:12345
}

console.log(ob);

// ! 1.JSON.stringify()

// this method is used to convert any javascript into json string.

let jsonData=JSON.stringify(ob)

console.log(jsonData);
console.log(typeof jsonData);

// ! 2.JSON.parse()

// this method is used to convert json string data into javascript object.

let parseob=JSON.parse(jsonData)
console.log(parseob);



