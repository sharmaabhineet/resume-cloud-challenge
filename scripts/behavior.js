function get_content(fragment_id, callback) {
  var content = {
    home: "home-page.html",
    about: "about-page.html",
    contact: "contact-page.html",
  };

  var xhr =
    typeof XMLHttpRequest != "undefined"
      ? new XMLHttpRequest()
      : new ActiveXObject("Microsoft.XMLHTTP");
      console.log('Loading ' +content[fragment_id])
  xhr.open("get", content[fragment_id], true);
  xhr.onreadystatechange = function () {
    if (xhr.readyState == 4 && xhr.status == 200) {
      callback(xhr.responseText);
    }
  };
  xhr.send();
}

function set_inner_html(elm, html) {
  elm.innerHTML = html;
  
  Array.from(elm.querySelectorAll("script"))
    .forEach( oldScriptEl => {
      const newScriptEl = document.createElement("script");
      
      Array.from(oldScriptEl.attributes).forEach( attr => {
        newScriptEl.setAttribute(attr.name, attr.value) 
      });
      
      const scriptText = document.createTextNode(oldScriptEl.innerHTML);
      newScriptEl.appendChild(scriptText);
      
      oldScriptEl.parentNode.replaceChild(newScriptEl, oldScriptEl);
  });
}

function load_content() {
  var fragment_id = location.hash.substring(1);
  var callback = function (content) {
    var main_body = this.document.getElementById("main_article");
    // main_body.innerHTML = content;
    set_inner_html(main_body, content);
  };
  get_content(fragment_id, callback);
}

// This will listen for the fragment identifier change
window.addEventListener("hashchange", function () {
  load_content();
});

function default_hash() {
  if (!location.hash) {
    location.hash = "#home";
  }
  load_content();
}