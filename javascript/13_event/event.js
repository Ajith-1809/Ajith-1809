let wish = ()=>{
    console.log("welcome to event");
    
}

let changecolor = ()=>{
    let header = document.getElementsByTagName("header")
    console.log(header[0]);

    header[0].style.backgroundColor = "red"
    
}

let changecolor2 = ()=>{
     let header = document.getElementsByTagName("header")
    console.log(header[0]);

    header[0].style.backgroundColor = "bisque"
}

let btn2 = document.querySelector(".btn2")
console.log(btn2);

btn2.addEventListener("dblclick", ()=>{
    alert("I am dbl click event")
})

let section = document.querySelector("section")
console.log(section);

section.addEventListener("mouseover", ()=>{
    section.style.backgroundColor = "green"
})

section.addEventListener("mouseleave", ()=>{
    section.style.backgroundColor = "aquamarine"
})

let box2 = document.getElementById("box2")
console.log(box2);

box2.addEventListener("click", ()=>{
    let box1 = document.getElementById("box1")
    box2.innerHTML = box1.innerHTML
})






