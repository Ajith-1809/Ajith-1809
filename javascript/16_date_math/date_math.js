// ! Date Object

// date object is used to work with dates and times in JavaScript.
// It is a built-in object that provides methods for getting and setting dates and times.
// It can be used to create a date object for the current date and time, or for a specific date and time.
// It can also be used to perform date arithmetic, such as adding or subtracting days, months, or years from a date.

let now = new Date()

console.log(now);

console.log("year is " + now.getFullYear());
console.log("today is " + now.getDate());
// console.log(now.getTime());
console.log("month is " + (now.getMonth() + 1)); // months are 0 indexed
console.log("day is " + now.getDay()); // 0 is sunday, 1 is monday, etc.
console.log("hours is " + now.getHours());
console.log("minutes is " + now.getMinutes());
console.log("seconds is " + now.getSeconds());

let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

console.log("month is " + months[now.getMonth()]);

let getTime = () => {
    let date = new Date();

    let h = date.getHours();
    let m = date.getMinutes();
    let s = date.getSeconds();
    let period = h >= 12 ? "PM" : "AM";
    if (h > 12) {
        h = h - 12;
    } else if (h <= 12) {
        h = h; // midnight case
    }
    h = (h<10) ? "0" + h : h;
    m = (m<10) ? "0" + m : m;
    s = (s<10) ? "0" + s : s;
    let time =document.querySelector(".inner");
    time.innerHTML = `${h}:${m}:${s} ${period}`;
}
getTime();
setInterval(getTime, 1000);

// ! Math Object
// Math object is a built-in object in JavaScript that provides mathematical constants and functions.

console.log(Math.sqrt(16)); // square root of 16
console.log(Math.ceil(4.2)); // rounds up to the nearest integer
console.log(Math.floor(4.8)); // rounds down to the nearest integer
console.log(Math.round(4.5)); // rounds to the nearest integer
console.log(Math.round(4.3));
console.log(Math.max(1, 2, 3, 4, 5)); // returns the largest of the given numbers
console.log(Math.min(1, 2, 3, 4, 5)); // returns the smallest of the given numbers

console.log(Math.random()*100); // returns a random number between 0 and 100
console.log(Math.floor(Math.random()*100)); // returns a random integer between 0 and 99
console.log(Math.PI); // returns the value of pi


