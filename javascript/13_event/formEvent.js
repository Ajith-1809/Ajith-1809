let form = document.querySelector("form");

form.addEventListener("submit", (e) => {
    e.preventDefault();

    let username = document.getElementById("name").value;
    let userpass = document.getElementById("pass").value;
    let userphone = document.getElementById("phone").value;

    console.log(username, userpass, userphone);

    document.getElementById("name").value = "";
    document.getElementById("pass").value = "";
    document.getElementById("phone").value = "";
    console.log("submitted");
});

let select = document.getElementById("select");
select.addEventListener("change", (e) => {
    console.log(e.target.value);
    let outer = document.querySelector(".outer");
    outer.style.backgroundColor = e.target.value;
    console.log(outer.style.backgroundColor);
});