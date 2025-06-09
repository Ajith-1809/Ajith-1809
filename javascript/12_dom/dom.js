// ! How to target Element from js

// ! 1.targeting element by id

// ? method name : document.getElementById("")

let logo = document.getElementById("logo")

console.log(logo);


let about = document.getElementById("about")

console.log(about);


// ! 2.targetting by the class name

let card = document.getElementsByClassName("card")

console.log(card);


// ! 3.targetting element by the tag name

let list = document.getElementsByTagName("li")

console.log(list);

// ! 4.targetting element by selector
// ? it's always select 1st element in the HTML page while using query selector.

let c = document.querySelector(".card")

console.log(c);

// ! 2.How to write inside the element 

// ? 1.innerHTML

let boxes = document.getElementsByClassName("box")
boxes[1].innerHTML =`<h1>I am box2</h1>
<p>we are coming</p>
<button>get started</button>`

// ? 2.innerText

boxes[2].innerText = `I am innertext`

// ! target the first card and print what is written inside that

// ? it's always select 1st element in the HTML page while using query selector.

let firstcard = document.querySelector(".card")
console.log(firstcard.innerHTML);
console.log(firstcard.innerText);

// ! 3.How to style

let firstbox = boxes[0]
console.log(firstbox);
firstbox.style.backgroundColor = 'red'
firstbox.innerHTML = `<h1>I am first box</h1>`
firstbox.style.color = 'white'

// ! 4.How to add class

let lastbox = boxes[2]
lastbox.classList.add("dark")
lastbox.classList.add("san")
lastbox.classList.add("king")
console.log(lastbox.classList);

// ! 5.How to remove class

lastbox.classList.remove("king")
console.log(lastbox.classList);

// ! write something inside lastbox and apply css by class

lastbox.innerHTML = `<h1>I am last box</h1>
<p>lorem</p>`

// ! 6.How to create element

let card1= document.querySelector(".card")
let newdiv = document.createElement("div")
newdiv.classList.add("div1")
console.log(newdiv.classList);
// card1.append(newdiv)
card1.prepend(newdiv)
// card1.after(newdiv)
// card1.before(newdiv)









